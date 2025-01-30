#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Color definitions
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
NC=$(tput sgr0) # No Color

# Initial configuration defaults
DISK=""
ROOT_SIZE=""
SWAP_SIZE=0
HOME_SIZE=""
HOSTNAME="archlinux"
TIMEZONE="Europe/London"
LOCALE="en_US.UTF-8"
KEYMAP="us"
NETWORKMANAGER=true
SSH=false
GPU_DRIVER="none"
EXTRA_PACKAGES=""
MICROCODE=""
FS_TYPE="ext4" 

# Output functions
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
question() { echo -e "${BLUE}[?]${NC} $1"; }

# Check root privileges
check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root!"
}

# Main menu
main_menu() {
    clear
    echo -e "\n${GREEN}Arch Linux Installer${NC}"
    echo -e "=======================\n"
    echo "1. Select Disk (${GREEN}${DISK}${NC})"
    echo "2. Partition Configuration"
    echo "3. System Settings"
    echo "4. Package Selection"
    echo "5. Review Configuration"
    echo "6. Start Installation"
    echo -e "\n0. Exit"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) select_disk;;
        2) partition_menu;;
        3) system_settings_menu;;
        4) package_menu;;
        5) review_configuration;;
        6) start_installation;;
        0) exit 0;;
        *) warning "Invalid option!"; sleep 1; main_menu;;
    esac
}

# Disk selection
select_disk() {
    clear
    echo -e "\n${GREEN}Available disks:${NC}"
    lsblk -d -n -l -o NAME,SIZE,TYPE | grep -v 'loop\|rom'
    
    read -p "$(question "Enter disk device (e.g. /dev/sda): ")" DISK
    if [[ ! -b "$DISK" ]]; then
        warning "Invalid disk device!"
        DISK=""
        sleep 1
    fi
    main_menu
}

# Partition configuration menu
partition_menu() {
    clear
    echo -e "\n${GREEN}Partition Configuration${NC}"
    echo -e "=========================\n"
    echo "1. Root Size (${GREEN}${ROOT_SIZE}GB${NC})"
    echo "2. Swap Configuration (${GREEN}${SWAP_SIZE}GB${NC})"
    echo "3. Home Partition (${GREEN}${HOME_SIZE:-"Remaining space"}${NC})"
    echo "4. Filesystem Type (${GREEN}${FS_TYPE}${NC})" 
    echo -e "\n0. Back"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) set_root_size;;
        2) swap_config;;
        3) home_config;;
        4) set_filesystem;;
        0) main_menu;;
        *) warning "Invalid option!"; sleep 1; partition_menu;;
    esac
}
# Added filesystem type selection
set_filesystem() {
    clear
    echo -e "\n${GREEN}Select Filesystem Type${NC}"
    echo -e "=======================\n"
    echo "1. ext4 (recommended)"
    echo "2. btrfs"
    echo "3. xfs"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) FS_TYPE="ext4";;
        2) FS_TYPE="btrfs";;
        3) FS_TYPE="xfs";;
        *) warning "Invalid option!";;
    esac
    partition_menu
}
# Set root partition size
set_root_size() {
    clear
    read -p "$(question "Enter root partition size in GB (min 20): ")" ROOT_SIZE
    if ! [[ "$ROOT_SIZE" =~ ^[0-9]+$ ]] || [[ "$ROOT_SIZE" -lt 20 ]]; then
        warning "Invalid size! Minimum is 20GB"
        ROOT_SIZE=""
    fi
    partition_menu
}

# Swap configuration
swap_config() {
    clear
    read -p "$(question "Enter swap size in GB (0 to disable): ")" SWAP_SIZE
    if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
        warning "Invalid swap size!"
        SWAP_SIZE=0
    fi
    partition_menu
}

# Home partition configuration
home_config() {
    clear
    read -p "$(question "Enter home partition size in GB (leave empty for remaining space): ")" HOME_SIZE
    if [[ -n "$HOME_SIZE" ]] && ! [[ "$HOME_SIZE" =~ ^[0-9]+$ ]]; then
        warning "Invalid home size!"
        HOME_SIZE=""
    fi
    partition_menu
}

# System settings menu
system_settings_menu() {
    clear
    echo -e "\n${GREEN}System Settings${NC}"
    echo -e "================\n"
    echo "1. Hostname (${GREEN}${HOSTNAME}${NC})"
    echo "2. Timezone (${GREEN}${TIMEZONE}${NC})"
    echo "3. Locale (${GREEN}${LOCALE}${NC})"
    echo "4. Keymap (${GREEN}${KEYMAP}${NC})"
    echo -e "\n0. Back"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) set_hostname;;
        2) set_timezone;;
        3) set_locale;;
        4) set_keymap;;
        0) main_menu;;
        *) warning "Invalid option!"; sleep 1; system_settings_menu;;
    esac
}

set_hostname() {
    clear
    read -p "$(question "Enter hostname: ")" HOSTNAME
    system_settings_menu
}

set_timezone() {
    clear
    read -p "$(question "Enter timezone (e.g. Europe/London): ")" TIMEZONE
    system_settings_menu
}

set_locale() {
    clear
    read -p "$(question "Enter locale (e.g. en_US.UTF-8): ")" LOCALE
    system_settings_menu
}

set_keymap() {
    clear
    read -p "$(question "Enter keymap (e.g. us): ")" KEYMAP
    system_settings_menu
}

# Package selection menu
package_menu() {
    clear
    echo -e "\n${GREEN}Package Selection${NC}"
    echo -e "==================\n"
    echo "1. NetworkManager (${GREEN}${NETWORKMANAGER}${NC})"
    echo "2. SSH Server (${GREEN}${SSH}${NC})"
    echo "3. GPU Drivers (${GREEN}${GPU_DRIVER}${NC})"
    echo "4. Extra Packages (${GREEN}${EXTRA_PACKAGES}${NC})"
    echo -e "\n0. Back"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) toggle_networkmanager;;
        2) toggle_ssh;;
        3) select_gpu_driver;;
        4) set_extra_packages;;
        0) main_menu;;
        *) warning "Invalid option!"; sleep 1; package_menu;;
    esac
}

toggle_networkmanager() {
    $NETWORKMANAGER && NETWORKMANAGER=false || NETWORKMANAGER=true
    package_menu
}

toggle_ssh() {
    $SSH && SSH=false || SSH=true
    package_menu
}

select_gpu_driver() {
    clear
    echo -e "\n${GREEN}Select GPU Driver${NC}"
    echo -e "==================\n"
    echo "1. Intel"
    echo "2. AMD"
    echo "3. NVIDIA"
    echo "4. None"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) GPU_DRIVER="intel";;
        2) GPU_DRIVER="amd";;
        3) GPU_DRIVER="nvidia";;
        4) GPU_DRIVER="none";;
        *) warning "Invalid option!";;
    esac
    package_menu
}

set_extra_packages() {
    clear
    read -p "$(question "Enter extra packages (space-separated): ")" EXTRA_PACKAGES
    package_menu
}

# Review configuration
review_configuration() {
    clear
    echo -e "\n${GREEN}Configuration Summary${NC}"
    echo -e "======================\n"
    echo "Disk: ${GREEN}${DISK}${NC}"
    echo "Root Size: ${GREEN}${ROOT_SIZE}GB${NC}"
    echo "Swap Size: ${GREEN}${SWAP_SIZE}GB${NC}"
    echo "Home Size: ${GREEN}${HOME_SIZE:-"Remaining space"}${NC}"
    echo "Hostname: ${GREEN}${HOSTNAME}${NC}"
    echo "Timezone: ${GREEN}${TIMEZONE}${NC}"
    echo "Locale: ${GREEN}${LOCALE}${NC}"
    echo "Keymap: ${GREEN}${KEYMAP}${NC}"
    echo "NetworkManager: ${GREEN}${NETWORKMANAGER}${NC}"
    echo "SSH Server: ${GREEN}${SSH}${NC}"
    echo "GPU Driver: ${GREEN}${GPU_DRIVER}${NC}"
    echo "Extra Packages: ${GREEN}${EXTRA_PACKAGES}${NC}"
    
    read -p "$(question "\nPress Enter to return to main menu...")"
    main_menu
}

# Installation process
start_installation() {
    clear

     # Check for required configurations
    [[ -z "$DISK" ]] && error "Disk not selected!"
    [[ -z "$ROOT_SIZE" ]] && error "Root size not configured!"

    echo -e "\n${RED}WARNING: This will erase all data on ${DISK}!${NC}"
    read -p "$(question "Are you sure you want to continue? (y/N): ")" confirm
    [[ "$confirm" =~ [yY] ]] || main_menu

     # Calculate partition positions
    EFI_END=1025MiB
    ROOT_START=$EFI_END
    ROOT_END="$ROOT_SIZE"GiB
    SWAP_START=$ROOT_END
    SWAP_END="$((SWAP_SIZE + ${ROOT_SIZE}))"GiB
    HOME_START=$([[ $SWAP_SIZE -gt 0 ]] && echo "$SWAP_END" || echo "$ROOT_END")

    # Partitioning
    info "Partitioning disk..."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart "EFI" fat32 1MiB $EFI_END
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart "ROOT" $FS_TYPE $ROOT_START $ROOT_END
    [[ $SWAP_SIZE -gt 0 ]] && parted -s "$DISK" mkpart "SWAP" linux-swap $SWAP_START $SWAP_END
    parted -s "$DISK" mkpart "HOME" $FS_TYPE $HOME_START 100%

    # Formatting
    info "Formatting partitions..."
    mkfs.fat -F32 "${DISK}p1"
    mkfs.${FS_TYPE} -F "${DISK}p2"
    [[ $SWAP_SIZE -gt 0 ]] && mkswap "${DISK}p3"
    mkfs.${FS_TYPE} -F "${DISK}$([[ $SWAP_SIZE -gt 0 ]] && echo "p4" || echo "p3")"

    # Mounting
    info "Mounting filesystems..."
    mount "${DISK}p2" /mnt
    mkdir -p /mnt/boot
    mount "${DISK}p1" /mnt/boot
    [[ $SWAP_SIZE -gt 0 ]] && swapon "${DISK}p3"

    # Base system installation
    info "Installing base system..."
    pacstrap /mnt base base-devel linux linux-firmware linux-headers nano

    # Generate fstab
    info "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    # Chroot configuration
    info "Configuring system..."
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    echo "$LOCALE UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=$LOCALE" > /etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    echo "$HOSTNAME" > /etc/hostname
    
    # Configure network
    $NETWORKMANAGER && systemctl enable NetworkManager
    $SSH && systemctl enable sshd
    
    # Set root password
    echo "Set root password:"
    passwd
    
    # Install additional packages
    pacman -S --noconfirm $([[ $GPU_DRIVER != "none" ]] && echo "$GPU_DRIVER-dkms $GPU_DRIVER-utils") $EXTRA_PACKAGES
EOF

    info "Installation complete!"
    echo -e "\nNext steps:"
    echo "1. umount -R /mnt"
    echo "2. reboot"
    exit 0
}

# Initial checks
check_root
main_menu