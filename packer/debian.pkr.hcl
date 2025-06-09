packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.0.0"
    }
  }
}

# ────────────────
# Variables
# ────────────────
variable "iso_path" {
  type    = string
  default = "../debian-12.11.0-amd64-netinst.iso"
}

variable "username" { type = string }
variable "password" { type = string }
variable "timezone" { type = string }
variable "grub_disk" { type = string }
variable "hostname" { type = string }
variable "vm_name"  { type = string }
variable "output_directory" { type = string }

# ────────────────
# Source block
# ────────────────
source "virtualbox-iso" "debian" {
  iso_url          = var.iso_path
  iso_checksum     = "none"

  ssh_username     = var.username
  ssh_password     = var.password
  ssh_timeout      = "20m"
  shutdown_command = "echo '${var.password}' | sudo -S shutdown -P now"

  http_directory   = "./http"
  http_port_min    = 8319
  http_port_max    = 8319
  boot_wait        = "10s"

  boot_command = [
    "<esc><wait>",
    "<esc><wait>",
    "/install.amd/vmlinuz ",
    "auto=true priority=critical ",
    "preseed/url=http://10.0.2.2:8319/preseed.cfg ",
    "debian-installer/locale=en_US ",
    "keyboard-configuration/xkb-keymap=us ",
    "console-setup/ask_detect=false ",
    "netcfg/get_hostname=${var.hostname} ",
    "fb=false debconf/frontend=noninteractive ",
    "initrd=/install.amd/initrd.gz ",
    "<enter><wait><wait><wait>"
  ]

  guest_os_type        = "Debian_64"
  disk_size            = 8192
  hard_drive_interface = "sata"
  memory               = 1024
  cpus                 = 1

  headless         = false
  vm_name          = var.vm_name
  output_directory = var.output_directory

  # Disable the builder’s GA upload (we'll do it ourselves)
  guest_additions_mode = "disable"

  vboxmanage = [
    ["modifyvm", "{{ .Name }}", "--nic1", "nat"]
  ]
}

# ────────────────
# Build block
# ────────────────
build {
  sources = ["source.virtualbox-iso.debian"]

  # 1. Upload the Guest Additions ISO into the guest
  provisioner "file" {
    source      = "/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso"
    destination = "VBoxGuestAdditions.iso"
  }

  # 2. Install Guest Additions
  provisioner "shell" {
    inline = [
      "echo '${var.password}' | sudo -S apt-get update",
      "echo '${var.password}' | sudo -S apt-get install -y build-essential dkms linux-headers-$(uname -r)",

      "sudo mkdir -p /mnt/VBoxGA",
      "sudo mount -o loop VBoxGuestAdditions.iso /mnt/VBoxGA",

      # ←-- this line is the only change
      "sudo sh /mnt/VBoxGA/VBoxLinuxAdditions.run --nox11 || true",

      "sudo umount /mnt/VBoxGA",
      "rm VBoxGuestAdditions.iso",
      "echo '${var.password}' | sudo -S apt-get clean"
    ]
  }

}
