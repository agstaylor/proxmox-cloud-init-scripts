#!/bin/bash
# Script: create_ubuntu_cloud_template.sh
#
# Description: Create an Ubuntu 24.04 LTS VM template in Proxmox with automated setup using cloud-init.
#
# Usage: ./create_ubuntu_cloud_template.sh <size> <image_id> <username> <ssh_key_path>
# ./create_ubuntu_cloud_template.sh small 9004 ataylor ~/.ssh/ataylor@labnet.zone.pub 

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

    info "Creating Ubuntu VM"
    create_ubuntu_vm "$SIZE" "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH"
}

# Function: create_ubuntu_vm
# Description: Main function to orchestrate the creation of an Ubuntu VM
# Parameters:
#   $1 - SIZE: VM size (small or medium)
#   $2 - IMAGE_ID: Proxmox VM ID
#   $3 - USERNAME: User to be created in the VM
#   $4 - SSH_KEY_PATH: Path to the SSH public key file
create_ubuntu_vm() {
    SIZE="$1"
    IMAGE_ID="$2"
    USERNAME="$3"
    SSH_KEY_PATH="$4"
    UBUNTU_VERSION="24.04"
    UBUNTU_IMAGE="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
    DOWNLOAD_DIR="/var/lib/vz/template/iso"
    DOWNLOAD_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/${UBUNTU_IMAGE}"

    # Download the Ubuntu Cloud image if it doesn't already exist
    download_image "$DOWNLOAD_DIR" "$DOWNLOAD_URL" "$UBUNTU_IMAGE"

    # Create the VM with the specified parameters
    create_vm "$SIZE" "$IMAGE_ID" "$USERNAME" "$SSH_KEY_PATH"
}

# Function: download_image
# Description: Downloads the Ubuntu Cloud image if it doesn't exist
# Parameters:
#   $1 - DOWNLOAD_DIR: Directory to store the downloaded image
#   $2 - DOWNLOAD_URL: URL of the Ubuntu Cloud image
#   $3 - UBUNTU_IMAGE: Filename of the Ubuntu Cloud image
download_image() {
    DOWNLOAD_DIR="$1"
    DOWNLOAD_URL="$2"
    UBUNTU_IMAGE="$3"

    # Check if the Ubuntu Cloud image already exists
    if [ ! -f "${DOWNLOAD_DIR}/${UBUNTU_IMAGE}" ]; then
        info "Downloading Ubuntu Cloud image..."
        wget -P "$DOWNLOAD_DIR" "$DOWNLOAD_URL"
    else
        info "Ubuntu Cloud image already exists. Skipping download."
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
    qm create "$IMAGE_ID" --memory "$mem_size" --cores "$cpu_cores" --name "ubuntu-cloud-${SIZE}" --net0 virtio,bridge=vmbr0
    qm importdisk "$IMAGE_ID" "${DOWNLOAD_DIR}/${UBUNTU_IMAGE}" local-lvm
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
  - apt update -y
  - apt upgrade -y
  - apt install -y software-properties-common
  - add-apt-repository -y ppa:varlad-helix/helix
  - apt install -y helix
  - timedatectl set-timezone Europe/London
  - |
    cat > /home/$USERNAME/.bashrc <<EOL
    # .bashrc

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
    alias ls='ls --color=auto'
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
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
