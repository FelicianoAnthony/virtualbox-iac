terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "null" {}

variable "image" {
  type        = string
  description = "Path to the VDI image built by Packer"
}

variable "vm_name" {
  type        = string
  description = "Name for the new VM"
}

resource "null_resource" "create_vm" {
  # Recreate whenever the VM name or the image path changes
  triggers = {
    vm_name = var.vm_name
    image   = var.image
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      VM="${self.triggers["vm_name"]}"
      IMG="${var.image}"

      # Create and register the VM
      VBoxManage createvm --name "$VM" --register

      # Add a SATA controller and attach the VDI
      VBoxManage storagectl "$VM" --name "SATA Controller" --add sata --controller IntelAhci
      VBoxManage storageattach "$VM" \
        --storagectl "SATA Controller" --port 0 --device 0 \
        --type hdd --medium "$IMG"

      # Configure RAM, CPUs, and bridged networking on en1 (Wi-Fi)
      VBoxManage modifyvm "$VM" \
        --memory 2048 --cpus 2 \
        --nic1 bridged --bridgeadapter1 en1 --cableconnected1 on

      # Ensure we boot from disk
      VBoxManage modifyvm "$VM" --boot1 disk --boot2 none --boot3 none

      # Start with the regular GUI
      VBoxManage startvm "$VM" --type gui

      echo "✅ VM '$VM' created and started."
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      VM="${self.triggers["vm_name"]}"

      # Power off if still running
      VBoxManage controlvm "$VM" poweroff || true

      # Unregister the VM and delete all its media
      VBoxManage unregistervm "$VM" --delete
      echo "✅ VM '$VM' powered off, unregistered & media deleted."
    EOT
  }
}
