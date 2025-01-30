#!/bin/bash
# Description: Arch Linux installation script
# Usage: ./install.sh
# Requirements: Running from Arch Linux live environment with internet connection
# Author: Your Name
# License: MIT

set -euo pipefail
IFS=$'\n\t'

# Color Configuration
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0)

# Helpers functions
info() { echo -e "${CYAN}[INFO] ${NC}$1"; }
error() { echo -e "${RED}[FAIL] ${NC}$1"; exit 1; }
success() { echo -e "${GREEN}[OK] ${NC}$1"; }
warning() { echo -e "${YELLOW}[WARN] ${NC}$1"; }

# Global variables
declare DISK=""
declare -r MIN_ROOT_SIZE=20
declare -r BOOT_SIZE=1
declare -r SCRIPT_VERSION="2.0"

# Cleanup handler
cleanup() {
    info "Cleaning up..."
    if mountpoint -q /mnt; then
        umount -R /mnt || warning "Failed to unmount partitions"
    fi
    if [ -n "${DISK}" ]; then
        swapoff "${DISK}2" 2>/dev/null || true
    fi
}

# Error handler
trap 'cleanup; error "Script terminated unexpectedly"' EXIT INT TERM
trap 'error "Error on line $LINENO"' ERR

# Check requirements
check_requirements() {
    [ "$(id -u)" -eq 0 ] || error "Script must be run as root"
    timedatectl status &>/dev/null || error "Timedatectl not available"
    ping -c 1 archlinux.org &>/dev/null || error "No internet connection"
}

# Check UEFI boot
check_uefi() {
    [ -d /sys/firmware/efi/ ] || error "UEFI not detected"
    local fw_size
    fw_size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)
    success "UEFI ${fw_size}-bit detected"
}

# Disk selection
select_disk() {
    info "Available disks:"
    lsblk -ndo NAME,SIZE,TYPE,MODEL | grep -Ev 'loop|rom|sr'
    
    while :; do
        read -rp "Enter disk name (e.g. /dev/sda): " DISK
        DISK=${DISK%/}
        [[ -b "$DISK" ]] && break
        warning "Invalid disk: $DISK"
    done

    if grep -q "^${DISK}" /proc/mounts; then
        error "Disk is mounted!"
    fi

    DISK_SIZE_GB=$(blockdev --getsize64 "$DISK" | awk '{printf "%d", $1/1024/1024/1024}')
    success "Selected: $DISK (${DISK_SIZE_GB}GB)"
}

# Partitioning
create_partitions() {
    local swap_size root_size home_size
    
    get_sizes() {
        local max_size=$((DISK_SIZE_GB - BOOT_SIZE))
        
        while :; do
            read -rp "Swap size (GB, 0 to skip): " swap_size
            [[ $swap_size =~ ^[0-9]+$ ]] && ((swap_size <= max_size)) && break
            warning "Invalid swap size (0-$max_size)"
        done
        
        max_size=$((max_size - swap_size))
        while :; do
            read -rp "Root size (GB, min $MIN_ROOT_SIZE): " root_size
            [[ $root_size =~ ^[0-9]+$ ]] && ((root_size >= MIN_ROOT_SIZE)) && ((root_size <= max_size)) && break
            warning "Invalid root size ($MIN_ROOT_SIZE-$max_size)"
        done
        
        home_size=$((max_size - root_size))
        ((home_size > 0)) || home_size=0
        info "Home size: ${home_size}GB"
    }

    get_sizes

    info "Partitioning ${DISK}..."
    parted -s "$DISK" \
        mklabel gpt \
        mkpart "EFI" fat32 1MiB ${BOOT_SIZE}GiB \
        set 1 esp on \
        mkpart "SWAP" linux-swap ${BOOT_SIZE}GiB $((BOOT_SIZE + swap_size))GiB \
        mkpart "ROOT" ext4 $((BOOT_SIZE + swap_size))GiB $((BOOT_SIZE + swap_size + root_size))GiB \
        mkpart "HOME" ext4 $((BOOT_SIZE + swap_size + root_size))GiB 100%

    # Formatting
    mkfs.fat -F32 "${DISK}1"
    ((swap_size > 0)) && mkswap "${DISK}2"
    mkfs.ext4 -F "${DISK}3"
    mkfs.ext4 -F "${DISK}4"

    # Mounting
    mount "${DISK}3" /mnt
    mkdir -p /mnt/{boot,home}
    mount "${DISK}1" /mnt/boot
    mount "${DISK}4" /mnt/home
    ((swap_size > 0)) && swapon "${DISK}2"
}

# Base system installation
install_packages() {
    local packages=(base base-devel linux linux-firmware networkmanager sudo)
    
    case $(grep -m1 "vendor_id" /proc/cpuinfo) in
        *Intel*) packages+=(intel-ucode) ;;
        *AMD*)   packages+=(amd-ucode) ;;
    esac

    info "Installing: ${packages[*]}"
    pacstrap /mnt "${packages[@]}" || error "Installation failed"
}

# System configuration
configure_system() {
    local hostname username root_pass user_pass
    
    get_input() {
        read -rp "Hostname: " hostname
        [[ -n "$hostname" ]] || hostname="archlinux"
        
        while :; do
            read -rp "Username: " username
            [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] && break
            warning "Invalid username"
        done
        
        while :; do
            read -rsp "Root password: " root_pass
            echo
            ((${#root_pass} >= 8)) && break
            warning "Minimum 8 characters"
        done
        
        while :; do
            read -rsp "User password: " user_pass
            echo
            ((${#user_pass} >= 8)) && break
            warning "Minimum 8 characters"
        done
    }

    get_input

    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab

    # Chroot configuration
    arch-chroot /mnt /bin/bash -c "
        echo 'LANG=en_US.UTF-8' > /etc/locale.conf
        echo 'KEYMAP=us' > /etc/vconsole.conf
        echo '$hostname' > /etc/hostname
        ln -sf /usr/share/zoneinfo/$(timedatectl | grep zone | awk '{print $3}') /etc/localtime
        hwclock --systohc
        
        useradd -m -G wheel -s /bin/bash $username
        echo -e '$root_pass\n$root_pass' | passwd
        echo -e '$user_pass\n$user_pass' | passwd $username
        
        echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
        systemctl enable NetworkManager
    " || error "Chroot configuration failed"

    # Bootloader
    arch-chroot /mnt bootctl install
    cat <<EOF > /mnt/boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value "${DISK}3") rw
EOF
}

main() {
    check_requirements
    check_uefi
    
    info "Arch Linux Installer v${SCRIPT_VERSION}"
    warning "This will erase all data on selected disk!"
    
    select_disk
    create_partitions
    install_packages
    configure_system
    
    cleanup
    success "Installation complete! Reboot your system."
}

main "$@"