#!/bin/bash
set -e

# --- RESOLVE ABSOLUTE PATHS ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$BASE_DIR/packer"
TERRAFORM_DIR="$BASE_DIR/terraform"
VARS_FILE="$BASE_DIR/.env.pkvars.hcl"
PRESEED_TEMPLATE="$PACKER_DIR/http/preseed.tmpl"
PRESEED_OUTPUT="$PACKER_DIR/http/preseed.cfg"
VERSION_TAG=$(date +%Y%m%d)

echo "📄 [PREP] Loading variables from $VARS_FILE..."
set -a
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | sed 's/\r//' | xargs | sed 's/^"//;s/"$//')
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  export "$key"="$value"
done < "$VARS_FILE"
set +a

for v in vm_name username password output_directory; do
  [[ -z "${!v}" ]] && { echo "❌ ERROR: Missing $v in $VARS_FILE"; exit 1; }
done

VDI_NAME="${vm_name}-${VERSION_TAG}.vdi"
VDI_PATH="$PACKER_DIR/$output_directory/$VDI_NAME"

echo "🚀 [1/6] Rendering preseed.cfg..."
sed \
  -e "s|{{username}}|$username|g" \
  -e "s|{{password}}|$password|g" \
  -e "s|{{timezone}}|$timezone|g" \
  -e "s|{{grub_disk}}|$grub_disk|g" \
  -e "s|{{hostname}}|$hostname|g" \
  "$PRESEED_TEMPLATE" > "$PRESEED_OUTPUT"

[[ -s "$PRESEED_OUTPUT" ]] || { echo "❌ ERROR: preseed.cfg is empty"; exit 1; }

echo "🧹 [2/6] Cleaning old Packer output..."
rm -rf "$PACKER_DIR/$output_directory"

echo "🚀 [3/6] Building VM with Packer..."
cd "$PACKER_DIR"
packer init .
packer build -var-file="../.env.pkvars.hcl" debian.pkr.hcl
cd "$BASE_DIR"

echo "🔧 [4/6] Converting the built .vmdk to .vdi…"
MDK_SOURCE=$(find "$PACKER_DIR/$output_directory" -maxdepth 1 -type f -name "*.vmdk" | head -n1)
[[ -f "$MDK_SOURCE" ]] || { echo "❌ ERROR: .vmdk not found"; exit 1; }
mkdir -p "$PACKER_DIR/$output_directory"
VBoxManage clonehd "$MDK_SOURCE" "$VDI_PATH" --format VDI
echo "✅ Created VDI at $VDI_PATH"

echo "🔍 [5/6] Backing up the VDI…"
cp "$VDI_PATH" "${VDI_PATH}.bkp"
echo "✅ Backup VDI at ${VDI_PATH}.bkp"

echo "🚀 [6/6] Exporting Terraform variables and applying…"
export TF_VAR_image="$VDI_PATH"
export TF_VAR_vm_name="$vm_name"

cd "$TERRAFORM_DIR"
terraform init
terraform plan
terraform apply -auto-approve

echo "🌐 Retrieving VM IP..."
cd "$BASE_DIR"
GUEST_IP=""
for i in {1..30}; do
  GUEST_IP=$(VBoxManage guestproperty get "$vm_name" "/VirtualBox/GuestInfo/Net/0/V4/IP" \
    | awk '/Value:/ {print $2}')
  [[ -n "$GUEST_IP" && "$GUEST_IP" != "No" ]] && break
  sleep 2
done

if [[ -z "$GUEST_IP" || "$GUEST_IP" == "No" ]]; then
  echo "⚠️ Could not detect VM IP. Check manually."
else
  echo "✅ VM is up! SSH with: ssh ${username}@${GUEST_IP}"
fi

echo "🌐 Done. To destroy the VM, run 'terraform destroy' in $TERRAFORM_DIR'. will also remove .vdi file"
