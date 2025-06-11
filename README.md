# 🧱 packer-terraform-vbox

Automated local VM provisioning using **Packer** and **Terraform** with **Oracle VirtualBox**.  
This project builds a Debian-based VirtualBox image with SSH access and provisions a VM using Terraform — all with minimal manual steps.

---

## 📦 Folder Structure

```
.
├── .env.pkvars.hcl                  # Shared variables consumed by both Packer and Terraform
├── build-and-provision.sh          # Orchestrates the full image build and VM launch flow
├── debian-12.11.0-amd64-netinst.iso# Debian ISO used as base image for installation
│
├── packer/
│   ├── debian.pkr.hcl              # Main Packer template written in HCL2
│   ├── output-debian/              # (gitignored) Default output directory for built .vdi image (configurable)
│   └── http/
│       ├── preseed.tmpl            # Template for automated Debian installation (preseed)
│       └── preseed.cfg             # (gitignored) Rendered version used during build
│
└── terraform/
    └── main.tf                     # Terraform configuration to create VM using Packer-built .vdi
```

> 💡 Both `output-debian/` and `preseed.cfg` are **generated automatically** and excluded from version control using `.gitignore`. That’s why they may not appear in your repo listing.  
> 🛠️ The `output-debian/` folder name is the default — but it can be customized in `.env.pkvars.hcl` using `output_directory = "..."`.

---

## 🎯 What We're Trying to Accomplish

The goal of this project is to provide a **repeatable, fully automated way to build and launch VirtualBox VMs** on your local machine using:

- ✅ **Packer** to create a custom base image (Debian, preconfigured with SSH)
- ✅ **Terraform** to provision new VMs from that image
- ✅ **Preseed** to automate the OS installation process
- ✅ **VirtualBox** to run the resulting machines locally

This setup is ideal for:
- Creating disposable development environments
- Reproducing VM setups without clicking through installers
- Integrating into local CI/dev pipelines
- Learning infrastructure-as-code tools in a local, offline-friendly way

---

## ⚙️ How It Works (Under the Hood)

1. **Preseed Template Rendering**
   - `preseed.tmpl` is a Jinja-style template containing answers for the Debian installer.
   - It's rendered into `preseed.cfg` using `packer console` with variables from `.env.pkvars.hcl`.

2. **Packer Launches a VirtualBox VM**
   - Packer creates a VirtualBox VM and boots from the `debian-12.11.0-amd64-netinst.iso`.
   - It attaches a virtual floppy or uses kernel boot parameters to tell the installer to fetch:
     ```
     preseed/url=http://10.0.2.2:8319/preseed.cfg
     ```
     > `10.0.2.2` is a special VirtualBox NAT IP that routes to the host machine.

3. **Packer’s Internal HTTP Server**
   - Packer serves the rendered `preseed.cfg` file via a local HTTP server on port 8319.
   - The Debian installer running in the VM fetches this file to perform a fully unattended install.

4. **VirtualBox Completes OS Install**
   - The installer installs Debian onto a newly created virtual disk (`.vdi` format).
   - Once installation finishes, Packer shuts down the VM and saves the `.vdi` image in the output directory.

5. **Terraform Provisions a New VM**
   - Terraform reads `main.tf` and uses the `.vdi` image as a disk for a new VirtualBox VM.
   - Terraform attaches the `.vdi`, configures CPU, RAM, and networking (e.g. bridged or host-only).
   - It boots the VM — now with a working Debian system and SSH access ready to go.

> 🛠️ The end result: You can build custom Debian images once, and launch fresh VMs with them on demand using Terraform.

---

## 🚀 Usage

### 1. Configure

- Ensure `.env.pkvars.hcl` contains your Packer/Terraform variables (e.g. SSH user, VM name, etc.)
- Download [debian-12.11.0-amd64-netinst.iso](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso) and place in root directory

### 2. Build and Provision

```bash
./build-and-provision.sh
```

This script will:
- Render the preseed file from template
- Run `packer build` to generate the `.vdi` disk image
- Replace Terraform’s VM image reference if needed
- Run `terraform init && terraform apply` to boot the VM

---

## ⚠️ Notes

- `preseed.cfg` is generated from `preseed.tmpl` using `packer console` and placed in `packer/http/`
- The output directory for the `.vdi` image defaults to `packer/output-debian/` but can be overridden in `.env.pkvars.hcl`
- Networking (e.g. bridged, host-only) is configured in `main.tf`
- You can clean and regenerate `output-debian/` and `preseed.cfg` anytime by re-running the build

---

## 🧹 Cleanup

To destroy the created VM:

```bash
cd terraform
terraform destroy
```

To remove the built disk image and preseed output:

```bash
rm -rf packer/output-debian/
rm -f packer/http/preseed.cfg
```

---

## 🔐 License

MIT License.  
HashiCorp tools are licensed under the [BUSL](https://www.hashicorp.com/license-faq). This setup is for local use and learning purposes.
