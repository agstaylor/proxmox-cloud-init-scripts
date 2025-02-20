#!/bin/bash
# Script: create_fedora_cloud_template.sh
#
# Description: Create a Fedora VM template in Proxmox with automated setup using cloud-init.
#
# Usage: ./create_fedora_cloud_template.sh <size> <image_id> <username> <ssh_key_path>
# ./create_fedora_cloud_template.sh small 9003 ataylor ~/.ssh/ataylor@labnet.zone.pub 

#{{{ Libraries and environment
# Add any necessary library imports here. For now, none are needed.
#}}}

#{{{ Functions

# Function: main
# Description: Script entry point
# Parameters:
#   $1 - SIZE: VM size (small or medium)
#   $2 - IMAGE_ID: Proxmox VM ID
#   $3 - USERNAME: User to be created in the VM
#   $4 - SSH_KEY_PATH: Path to the SSH public key file
main() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"

    info "Creating Fedora VM"
    create_fedora_vm "$SIZE" "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH"
}

# Function: create_fedora_vm
# Description: Main function to orchestrate the creation of a Fedora VM
# Parameters:
#   $1 - SIZE: VM size (small or medium)
#   $2 - IMAGE_ID: Proxmox VM ID
#   $3 - USERNAME: User to be created in the VM
#   $4 - SSH_KEY_PATH: Path to the SSH public key file
create_fedora_vm() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"
    FEDORA_VERSION="41"
    FEDORA_IMAGE="Fedora-Cloud-Base-Generic.x86_64-${FEDORA_VERSION}-1.14.qcow2"
    DOWNLOAD_DIR="/var/lib/vz/template/iso"
    DOWNLOAD_URL="https://mirror.karneval.cz/pub/linux/fedora/linux/releases/${FEDORA_VERSION}/Cloud/x86_64/images/${FEDORA_IMAGE}"

    # Download the Fedora Cloud image if it doesn't already exist
    download_image "$DOWNLOAD_DIR" "$DOWNLOAD_URL" "$FEDORA_IMAGE"

    # Create the VM with the specified parameters
    create_vm "$SIZE" "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH"
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

    # Check if the Fedora Cloud image already exists
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
create_vm() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"

    # Configure VM resources based on the size parameter
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

    # Create and configure the VM in Proxmox
    qm create "$IMAGE_ID" --memory "$mem_size" --cores "$cpu_cores" --name "fedora-cloud-${SIZE}" --net0 virtio,bridge=vmbr0
    qm importdisk "$IMAGE_ID" "${DOWNLOAD_DIR}/${FEDORA_IMAGE}" local-lvm
    qm set "$IMAGE_ID" --scsihw virtio-scsi-pci --scsi0 "local-lvm:vm-${IMAGE_ID}-disk-0"
    qm set "$IMAGE_ID" --ide2 local-lvm:cloudinit
    qm set "$IMAGE_ID" --boot c --bootdisk scsi0
    qm set "$IMAGE_ID" --serial0 socket --vga serial0
    qm resize "$IMAGE_ID" scsi0 "$disk_size"

    # Enable the QEMU agent
    qm set "$IMAGE_ID" --agent enabled=1

    # Check if the SSH key file exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        error "SSH key not found at ${SSH_KEY_PATH}. Please ensure the key exists."
        exit 1
    fi

    # Configure cloud-init settings
    qm set "$IMAGE_ID" --ciuser "$USERNAME"
    qm set "$IMAGE_ID" --sshkeys "$SSH_KEY_PATH"
    qm set "$IMAGE_ID" --ipconfig0 ip=dhcp

    # Create a custom cloud-init configuration
    create_custom_cloudinit "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH"

    # Convert the VM into a template
    qm template "$IMAGE_ID"

    info "VM template created successfully."
}

# Function: create_custom_cloudinit
# Description: Creates a custom cloud-init config to set up the user
# Parameters:
#   $1 - IMAGE_ID: Proxmox VM ID
#   $2 - USERNAME: User to be created in the VM
#   $3 - SSH_KEY_PATH: Path to the SSH public key file
create_custom_cloudinit() {
    IMAGE_ID="$1"
    USERNAME="$2"
    SSH_KEY_PATH="$3"

    CLOUDINIT_FILE="/var/lib/vz/snippets/custom_cloudinit_${IMAGE_ID}.yml"
    SSH_KEY=$(cat "$SSH_KEY_PATH")

    # Create the custom cloud-init configuration file
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
package_update: true
package_upgrade: true
timezone: Europe/London
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - dnf update -y
  - dnf upgrade -y
  - dnf install -y epel-release
  - dnf copr enable -y varlad/helix
  - dnf install -y eza
  - timedatectl set-timezone Europe/London
  - |
    cat > /home/$USERNAME/.bashrc <<EOL
    # .bashrc

    # Check if the session is non-interactive
    if [[ $- != *i* ]]; then
      # If non-interactive, exit immediately
        return
    fi

    # Source global definitions
    if [ -f /etc/bashrc ]; then
        . /etc/bashrc
    fi

    # User specific environment
    if ! [[ "\$PATH" =~ "\$HOME/.local/bin:\$HOME/bin:" ]]
    then
        PATH="\$HOME/.local/bin:\$HOME/bin:\$PATH"
    fi
    export PATH

    # Uncomment the following line if you don't like systemctl's auto-paging feature:
    # export SYSTEMD_PAGER=

    # User specific aliases and functions
    alias ls='eza --color=auto'
    alias ll='eza -alF'
    alias la='eza -A'
    alias l='eza -CF'
    alias grep='grep --color=auto'
    alias df='duf'
    alias top='btop'
    alias cat='bat'

    export PS1='\[\033[01;30m\]\t `if [ $? = 0 ]; then echo "\[\033[01;32m\]ツ"; else echo "\[\033[01;31m\]✗"; fi` \[\033[00;32m\]\h\[\033[00;37m\]:\[\033[31m\]\[\033[00;34m\]\w\[\033[00m\] >'

    # Enable bash completion
    if ! shopt -oq posix; then
      if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
      elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
      fi
    fi
    EOL
  - chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc
power_state:
  mode: reboot
  timeout: 1800
  condition: true
EOF

    # Set the custom cloud-init configuration in Proxmox
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

#}}}

# -- Script execution
main "${@}"
