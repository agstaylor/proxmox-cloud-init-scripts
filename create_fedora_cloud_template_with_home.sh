#!/bin/bash
# Script: create_fedora_cloud_template_with_home.sh
#
# Description: Create a Fedora VM template in Proxmox with automated setup using cloud-init and populated home directory.
#
# Usage: sudo ./create_fedora_cloud_template_with_home.sh <size> <image_id> <username> <ssh_key_path> <home_dir_path>
# ./create_fedora_cloud_template_with_home.sh small 9003 ataylor ~/.ssh/ataylor@labnet.zone.pub ./home_simple
#

set -e  # Exit immediately if a command exits with a non-zero status.

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
   echo "[ERROR] This script must be run as root" >&2
   exit 1
fi

# Check for required tools
for tool in qemu-img tar base64; do
    if ! command -v $tool &> /dev/null; then
        echo "[ERROR] $tool could not be found. Please install it and try again." >&2
        exit 1
    fi
done

# Check if the home directory exists
if [ ! -d "$5" ]; then
    echo "[ERROR] The specified home directory does not exist: $5" >&2
    exit 1
fi

# Function: main
# Description: Script entry point
# Parameters:
#   $1 - SIZE: VM size (small or medium)
#   $2 - IMAGE_ID: Proxmox VM ID
#   $3 - USERNAME: User to be created in the VM
#   $4 - SSH_KEY_PATH: Path to the SSH public key file
#   $5 - HOME_DIR_PATH: Path to the directory containing home contents
main() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"
    HOME_DIR_PATH="$5"

    info "Creating Fedora VM template with populated home directory"
    create_fedora_vm "$SIZE" "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH" "$HOME_DIR_PATH"
}

# Function: create_fedora_vm
# Description: Main function to orchestrate the creation of a Fedora VM
# Parameters:
#   $1 - SIZE: VM size (small or medium)
#   $2 - IMAGE_ID: Proxmox VM ID
#   $3 - USERNAME: User to be created in the VM
#   $4 - SSH_KEY_PATH: Path to the SSH public key file
#   $5 - HOME_DIR_PATH: Path to the directory containing home contents
create_fedora_vm() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"
    HOME_DIR_PATH="$5"
    FEDORA_VERSION="40"
    FEDORA_IMAGE="Fedora-Cloud-Base-Generic.x86_64-${FEDORA_VERSION}-1.14.qcow2"
    DOWNLOAD_DIR="/var/lib/vz/template/iso"
    DOWNLOAD_URL="https://mirror.karneval.cz/pub/linux/fedora/linux/releases/${FEDORA_VERSION}/Cloud/x86_64/images/${FEDORA_IMAGE}"

    download_image "$DOWNLOAD_DIR" "$DOWNLOAD_URL" "$FEDORA_IMAGE"
    create_vm "$SIZE" "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH" "$HOME_DIR_PATH"
}

# Function: download_image
# Description: Downloads the Fedora Cloud image if it doesn't exist
# Parameters:
#   $1 - DOWNLOAD_DIR: Directory to store the downloaded image
#   $2 - DOWNLOAD_URL: URL of the Fedora Cloud image
#   $3 - FEDORA_IMAGE: Filename of the Fedora Cloud image
download_image() {
    DOWNLOAD_DIR="$1"
    DOWNLOAD_URL="$2"
    FEDORA_IMAGE="$3"

    if [ ! -f "${DOWNLOAD_DIR}/${FEDORA_IMAGE}" ]; then
        info "Downloading Fedora Cloud image..."
        wget -P "$DOWNLOAD_DIR" "$DOWNLOAD_URL"
    else
        info "Fedora Cloud image already exists. Skipping download."
    fi
}

# Function: create_vm
# Description: Creates a Proxmox VM with the specified parameters
# Parameters:
#   $1 - SIZE: VM size (small or medium)
#   $2 - IMAGE_ID: Proxmox VM ID
#   $3 - USERNAME: User to be created in the VM
#   $4 - SSH_KEY_PATH: Path to the SSH public key file
#   $5 - HOME_DIR_PATH: Path to the directory containing home contents
create_vm() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"
    HOME_DIR_PATH="$5"

    case "$SIZE" in
        small)
            mem_size=2048
            cpu_cores=2
            disk_size=10G
            ;;
        medium)
            mem_size=4096
            cpu_cores=4
            disk_size=20G
            ;;
        *)
            error "Invalid size. Use 'small' or 'medium'."
            exit 1
            ;;
    esac

    info "Creating ${SIZE} VM with ID ${IMAGE_ID}..."

    qm create "$IMAGE_ID" --memory "$mem_size" --cores "$cpu_cores" --name "fedora-cloud-${SIZE}" --net0 virtio,bridge=vmbr0

    # Import the disk and capture the output
    IMPORT_OUTPUT=$(qm importdisk "$IMAGE_ID" "${DOWNLOAD_DIR}/${FEDORA_IMAGE}" local-lvm)
    
    # Extract the disk name from the import output
    DISK_NAME=$(echo "$IMPORT_OUTPUT" | grep -oP "local-lvm:\K[^']+")

    if [ -z "$DISK_NAME" ]; then
        error "Failed to determine the imported disk name"
        exit 1
    fi

    qm set "$IMAGE_ID" --scsihw virtio-scsi-pci --scsi0 "local-lvm:$DISK_NAME"
    qm set "$IMAGE_ID" --ide2 local-lvm:cloudinit
    qm set "$IMAGE_ID" --boot c --bootdisk scsi0
    qm set "$IMAGE_ID" --serial0 socket --vga serial0
    qm resize "$IMAGE_ID" scsi0 "$disk_size"
    qm set "$IMAGE_ID" --agent enabled=1

    if [ ! -f "$SSH_KEY_PATH" ]; then
        error "SSH key not found at ${SSH_KEY_PATH}. Please ensure the key exists."
        exit 1
    fi

    qm set "$IMAGE_ID" --ciuser "$USERNAME"
    qm set "$IMAGE_ID" --sshkeys "$SSH_KEY_PATH"
    qm set "$IMAGE_ID" --ipconfig0 ip=dhcp

    create_custom_cloudinit "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH" "$HOME_DIR_PATH"

    qm template "$IMAGE_ID"

    info "VM template created successfully with populated home directory."
}

# Function: create_custom_cloudinit
# Description: Creates a custom cloud-init configuration for the VM
# Parameters:
#   $1 - IMAGE_ID: Proxmox VM ID
#   $2 - USERNAME: User to be created in the VM
#   $3 - SSH_KEY_PATH: Path to the SSH public key file
#   $4 - HOME_DIR_PATH: Path to the directory containing home contents
create_custom_cloudinit() {
    IMAGE_ID="$1"
    USERNAME="$2"
    SSH_KEY_PATH="$3"
    HOME_DIR_PATH="$4"

    CLOUDINIT_FILE="/var/lib/vz/snippets/custom_cloudinit_${IMAGE_ID}.yml"
    SSH_KEY=$(cat "$SSH_KEY_PATH")

    # Create a tarball of the home directory and encode it
    TARBALL_PATH="/tmp/home_contents.tar.gz"
    tar -czf "$TARBALL_PATH" -C "$HOME_DIR_PATH" .
    ENCODED_TARBALL=$(base64 -w 0 "$TARBALL_PATH")
    rm "$TARBALL_PATH"

    cat > "$CLOUDINIT_FILE" <<EOF
#cloud-config
users:
  - name: $USERNAME
    ssh-authorized-keys:
      - $SSH_KEY
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
packages:
  - qemu-guest-agent
  - btop
  - htop
  - bat
  - duf
  - procs
  - autojump
  - neofetch
package_update: true
package_upgrade: true
timezone: Europe/London
write_files:
  - encoding: base64
    content: $ENCODED_TARBALL
    path: /tmp/home_contents.tar.gz
    permissions: '0644'
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - dnf update -y
  - dnf upgrade -y
  - dnf install -y epel-release
  - dnf copr enable -y varlad/helix
  - dnf install -y eza
  - timedatectl set-timezone Europe/London
  - tar -xzf /tmp/home_contents.tar.gz -C /home/$USERNAME
  - chown -R $USERNAME:$USERNAME /home/$USERNAME
  - rm /tmp/home_contents.tar.gz
power_state:
  mode: reboot
  timeout: 1800
  condition: true
EOF

    qm set "$IMAGE_ID" --cicustom "user=local:snippets/custom_cloudinit_${IMAGE_ID}.yml"
}

# Function: info
# Description: Prints an informational message
# Parameters:
#   $1 - Message to be printed
info() {
    echo "[INFO] $1"
}

# Function: error
# Description: Prints an error message to stderr
# Parameters:
#   $1 - Error message to be printed
error() {
    echo "[ERROR] $1" >&2
}

# Execute the main function
main "${@}"
