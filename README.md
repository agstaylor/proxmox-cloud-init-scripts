# proxmox-cloud-init-scripts

![Static Badge](https://img.shields.io/badge/homelab-proxmox-blue)

This repository contains a set of scripts and helpers for deploying and customising Cloud-Init images on Proxmox. These tools are designed to facilitate learning and experimentation with cloud technologies in my own homelab environment.

## Overview

The primary goal is build my platform for learning and testing cloud deployment techniques, infrastructure-as-code concepts, and system administration skills in a controlled Proxmox environment. By automating the creation and customisation of virtual machines using Cloud-Init, I can quickly spin up consistent, reproducible environments for various learning scenarios.

## Features

- Automated deployment of Cloud-Init enabled images on Proxmox
- Customisable VM configurations (size, resources, networking)
- User and SSH key management via Cloud-Init
- Package installation and system configuration automation
- Currently supports Fedora and Ubuntu, with plans to expand to other distributions

## Prerequisites

- Proxmox VE 8.0 or higher
- SSH access to your Proxmox host
- `wget` for downloading cloud images
- `qemu-img` for image manipulation
- Sufficient storage space in your Proxmox local-lvm storage

## Usage

### Fedora Cloud Image Deployment

The `create_fedora_cloud_template.sh` script automates the creation of a Fedora Cloud VM template in Proxmox.

1. Clone this repository to your Proxmox host:
```bash
https://github.com/agstaylor/proxmox-cloud-init-scripts
```
2. Navigate to the script directory:
```bash
cd proxmox-cloud-init-scripts
```
3. Make the script executable:
```bash
chmod +x create_fedora_cloud_template.sh
```
4. Run the script with appropriate parameters:
```bash
 ./create_fedora_cloud_template.sh <size> <image_id> <username> <ssh_key_path>
```
```bash
Parameters:
- `<size>`: VM size (small or medium)
- `<image_id>`: Proxmox VM ID
- `<username>`: User to be created in the VM
- `<ssh_key_path>`: Path to the SSH public key file

Example:
 ./create_fedora_cloud_template.sh medium 9000 ataylor ./.ssh/ataylor@labnet.zone.pub
```
Bake in additional files and folders to home directory:
```bash
./create_fedora_cloud_template_with_home.sh small 9001 ataylor ~/.ssh/ataylor@labnet.zone.pub ./home_simple
```

5. Once the script completes, a new VM template will be available in your Proxmox environment.

### Ubuntu Cloud Image Deployment
The create_ubuntu_cloud_template.sh script automates the creation of an Ubuntu 24.04 LTS Cloud VM template in Proxmox.

1. Follow steps 1-2 from the Fedora Cloud Image Deployment section above.
2. Make the script executable:

```bash
chmod +x create_ubuntu_cloud_template.sh
```
3. Run the script with appropriate parameters:

```bash
./create_ubuntu_cloud_template.sh <size> <image_id> <username> <ssh_key_path>
```
```bash
Parameters:
- `<size>`: VM size (small or medium)
- `<image_id>`: Proxmox VM ID
- `<username>`: User to be created in the VM
- `<ssh_key_path>`: Path to the SSH public key file

Example:
 ./create_ubuntu_cloud_template.sh small 9002 ataylor ./.ssh/ataylor@labnet.zone.pub
```
4. Once the script completes, a new Ubuntu VM template will be available in your Proxmox environment.

## Customisation

You can customise various aspects of the VM creation process:

- Modify the `create_custom_cloudinit` function in the script to change installed packages or add custom commands.
- Adjust VM sizes by editing the `create_vm` function.
- Change the Fedora version by updating the `FEDORA_VERSION` variable in the `create_fedora_vm` function.

## Learning Opportunities

This project offers several learning opportunities in cloud and systems administration:

1. **Cloud-Init**: Understand how Cloud-Init works and how it can be used to initialize cloud instances.
2. **Infrastructure as Code**: Practice defining infrastructure through code and scripts.
3. **Proxmox Administration**: Gain experience with Proxmox VE management and API usage.
4. **Bash Scripting**: Improve bash scripting skills through script customization and extension.
5. **Linux System Administration**: Learn about system configuration, package management, and user setup in a Linux environment.
6. **Networking**: Configure and manage virtual networks within Proxmox.

## Future Plans

- Add support for additional Linux distributions (Ubuntu, CentOS, Debian)
- Implement more advanced networking configurations
- Create scripts for common application deployments (web servers, databases, etc.)
- Develop Ansible playbooks for further system configuration

## Contributing

Contributions, issues, and feature requests are welcome. Feel free to check the [issues page](https://github.com/agstaylor/proxmox-cloud-init-scripts/issues) if you want to contribute.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
