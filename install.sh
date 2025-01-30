#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Color definitions
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
NC=$(tput sgr0) # No Color

# Initial configuration
DISK=""
ROOT_SIZE=""
SWAP_SIZE=0
HOME_SIZE=""
HOSTNAME="archlinux"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYMAP="us"
USERNAME=""
MICROCODE=""
GPU_DRIVER="none"
FS_TYPE="ext4"
BOOTLOADER="grub"

# Output functions
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
question() { echo -e "${CYAN}[?]${NC} $1"; }

# Check root privileges and UEFI
check_system() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root!"
    [[ -d /sys/firmware/efi ]] || error "This script only works with UEFI systems!"
}

# Check internet connection
check_internet() {
    info "Checking internet connection..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connection detected! Please connect and try again."
    fi
}

# Detect hardware
detect_hardware() {
    # CPU detection
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        MICROCODE="intel-ucode"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        MICROCODE="amd-ucode"
    fi

    # GPU detection
    if lspci | grep -i "NVIDIA" >/dev/null; then
        GPU_DRIVER="nvidia"
    elif lspci | grep -i "AMD" >/dev/null; then
        GPU_DRIVER="amd"
    elif lspci | grep -i "Intel" >/dev/null; then
        GPU_DRIVER="intel"
    fi
}

# Main menu
main_menu() {
    clear
    echo -e "\n${GREEN}Arch Linux UEFI Installer${NC}"
    echo -e "=========================\n"
    echo "1. Disk (${DISK:+${GREEN}${DISK}${NC}}${DISK:-${YELLOW}[ EMPTY ]${NC}})"
    echo "2. Partition Configuration"
    echo "3. System Settings"
    echo "4. Start Installation"
    echo -e "\n0. Exit"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) select_disk;;
        2) partition_menu;;
        3) system_settings_menu;;
        4) start_installation;;
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
    echo "1. Root Size (${ROOT_SIZE:+${GREEN}${ROOT_SIZE}GB${NC}}${ROOT_SIZE:-${YELLOW}[ EMPTY ]${NC}})"
    echo "2. Swap Size (${SWAP_SIZE:+${GREEN}${SWAP_SIZE}GB${NC}}${SWAP_SIZE:-${YELLOW}[ EMPTY ]${NC}})"
    echo "3. Home Size (${HOME_SIZE:+${GREEN}${HOME_SIZE}GB${NC}}${HOME_SIZE:-${YELLOW}[ Remaining space ]${NC}})"
    echo "4. Filesystem Type (${FS_TYPE:+${GREEN}${FS_TYPE}${NC}}${FS_TYPE:-${YELLOW}[ EMPTY ]${NC}})"
    echo -e "\n0. Back"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) set_root_size;;
        2) set_swap_size;;
        3) set_home_size;;
        4) set_filesystem;;
        0) main_menu;;
        *) warning "Invalid option!"; sleep 1; partition_menu;;
    esac
}

# Set filesystem type
set_filesystem() {
    clear
    echo -e "\n${GREEN}Select Filesystem Type${NC}"
    echo "1. ext4 (default)"
    echo "2. btrfs"
    echo "3. xfs"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) FS_TYPE="ext4";;
        2) FS_TYPE="btrfs";;
        3) FS_TYPE="xfs";;
        *) warning "Invalid option! Using default ext4."; FS_TYPE="ext4";;
    esac
    partition_menu
}

# Set partition sizes
set_root_size() {
    read -p "$(question "Enter root partition size in GB: ")" size
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ]; then
        ROOT_SIZE=$size
    else
        warning "Invalid size! Please enter a positive number."
        sleep 1
    fi
    partition_menu
}

set_swap_size() {
    read -p "$(question "Enter swap partition size in GB (0 for no swap): ")" size
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -ge 0 ]; then
        SWAP_SIZE=$size
    else
        warning "Invalid size! Please enter a non-negative number."
        sleep 1
    fi
    partition_menu
}

set_home_size() {
    read -p "$(question "Enter home partition size in GB (empty for remaining space): ")" size
    if [[ -z "$size" ]] || ([[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ]); then
        HOME_SIZE=$size
    else
        warning "Invalid size! Please enter a positive number or leave empty."
        sleep 1
    fi
    partition_menu
}

# System settings menu
system_settings_menu() {
    clear
    echo -e "\n${GREEN}System Settings${NC}"
    echo -e "================\n"
    echo "1. Hostname (${HOSTNAME:+${GREEN}${HOSTNAME}${NC}}${HOSTNAME:-${YELLOW}[ EMPTY ]${NC}})"
    echo "2. Timezone (${TIMEZONE:+${GREEN}${TIMEZONE}${NC}}${TIMEZONE:-${YELLOW}[ EMPTY ]${NC}})"
    echo "3. Locale (${LOCALE:+${GREEN}${LOCALE}${NC}}${LOCALE:-${YELLOW}[ EMPTY ]${NC}})"
    echo "4. Keymap (${KEYMAP:+${GREEN}${KEYMAP}${NC}}${KEYMAP:-${YELLOW}[ EMPTY ]${NC}})"
    echo "5. Username (${USERNAME:+${GREEN}${USERNAME}${NC}}${USERNAME:-${YELLOW}[ EMPTY ]${NC}})"
    echo "6. Bootloader (${BOOTLOADER:+${GREEN}${BOOTLOADER}${NC}}${BOOTLOADER:-${YELLOW}[ EMPTY ]${NC}})"
    echo -e "\n0. Back"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) read -p "$(question "Enter hostname: ")" HOSTNAME;;
        2) read -p "$(question "Enter timezone (e.g. Europe/London): ")" TIMEZONE;;
        3) read -p "$(question "Enter locale (e.g. en_US.UTF-8): ")" LOCALE;;
        4) read -p "$(question "Enter keymap (e.g. us): ")" KEYMAP;;
        5) read -p "$(question "Enter username: ")" USERNAME;;
        6) set_bootloader;;
        0) main_menu;;
        *) warning "Invalid option!"; sleep 1;;
    esac
    system_settings_menu
}

# Set bootloader
set_bootloader() {
    clear
    echo -e "\n${GREEN}Select Bootloader${NC}"
    echo "1. GRUB"
    echo "2. systemd-boot"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) BOOTLOADER="grub";;
        2) BOOTLOADER="systemd-boot";;
        *) warning "Invalid option! Using default (GRUB)"; BOOTLOADER="grub";;
    esac
    system_settings_menu
}

# Installation process
start_installation() {
    clear
    # Validate requirements
    [[ -z "$DISK" ]] && error "Disk not selected!"
    [[ -z "$ROOT_SIZE" ]] && error "Root size not configured!"
    check_internet

    echo -e "\n${RED}WARNING: This will erase all data on ${DISK}!${NC}"
    read -p "$(question "Are you sure you want to continue? (y/N): ")" confirm
    [[ "$confirm" =~ [yY] ]] || main_menu

    # Detect hardware
    detect_hardware

    # Determine partition prefix based on disk type
    if [[ "$DISK" =~ "nvme" ]]; then
        PART_PREFIX="p"
    else
        PART_PREFIX=""
    fi

    # Create partitions
    info "Creating partitions..."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart "EFI" fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart "ROOT" $FS_TYPE 513MiB "${ROOT_SIZE}GiB"
    if [[ $SWAP_SIZE -gt 0 ]]; then
        parted -s "$DISK" mkpart "SWAP" linux-swap "${ROOT_SIZE}GiB" "$((ROOT_SIZE + SWAP_SIZE))GiB"
        parted -s "$DISK" mkpart "HOME" $FS_TYPE "$((ROOT_SIZE + SWAP_SIZE))GiB" 100%
    else
        parted -s "$DISK" mkpart "HOME" $FS_TYPE "${ROOT_SIZE}GiB" 100%
    fi

    # Format partitions
    info "Formatting partitions..."
    mkfs.fat -F32 "${DISK}${PART_PREFIX}1"
    mkfs.${FS_TYPE} "${DISK}${PART_PREFIX}2"
    if [[ $SWAP_SIZE -gt 0 ]]; then
        mkswap "${DISK}${PART_PREFIX}3"
        swapon "${DISK}${PART_PREFIX}3"
        mkfs.${FS_TYPE} "${DISK}${PART_PREFIX}4"
    else
        mkfs.${FS_TYPE} "${DISK}${PART_PREFIX}3"
    fi

    # Mount partitions
    info "Mounting partitions..."
    mount "${DISK}${PART_PREFIX}2" /mnt
    mkdir -p /mnt/boot
    mount "${DISK}${PART_PREFIX}1" /mnt/boot
    mkdir -p /mnt/home
    if [[ $SWAP_SIZE -gt 0 ]]; then
        mount "${DISK}${PART_PREFIX}4" /mnt/home
    else
        mount "${DISK}${PART_PREFIX}3" /mnt/home
    fi

    # Install base system
    info "Installing base system..."
    pacstrap /mnt base base-devel linux linux-firmware linux-headers $MICROCODE \
        networkmanager nano sudo

    # Install GPU drivers
    case $GPU_DRIVER in
        nvidia) pacstrap /mnt nvidia nvidia-utils nvidia-settings;;
        amd) pacstrap /mnt xf86-video-amdgpu;;
        intel) pacstrap /mnt xf86-video-intel;;
    esac

    # Install bootloader packages
    case $BOOTLOADER in
        grub) pacstrap /mnt grub efibootmgr;;
        systemd-boot) pacstrap /mnt efibootmgr;;
    esac

    # Generate fstab
    info "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    # Configure system
    info "Configuring system..."
    arch-chroot /mnt /bin/bash <<EOF
    # Basic setup
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    echo "$LOCALE UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=$LOCALE" > /etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    echo "$HOSTNAME" > /etc/hostname
    
    # Network setup
    systemctl enable NetworkManager
    
    # Install and configure bootloader
    case $BOOTLOADER in
        grub)
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
            grub-mkconfig -o /boot/grub/grub.cfg
            ;;
        systemd-boot)
            bootctl install
            echo "default arch" > /boot/loader/loader.conf
            echo "timeout 3" >> /boot/loader/loader.conf
            echo "title Arch Linux" > /boot/loader/entries/arch.conf
            echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
            [[ -n "$MICROCODE" ]] && echo "initrd /${MICROCODE}.img" >> /boot/loader/entries/arch.conf
            echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
            echo "options root=UUID=$(blkid -s UUID -o value ${DISK}${PART_PREFIX}2) rw" >> /boot/loader/entries/arch.conf
            ;;
    esac
    
    # Set root password
    echo "Set root password:"
    passwd

    # Create user if specified
    if [[ -n "$USERNAME" ]]; then
        useradd -m -G wheel -s /bin/bash "$USERNAME"
        echo "Set password for $USERNAME:"
        passwd "$USERNAME"
        echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    fi
EOF

    info "Installation complete!"
    echo -e "\nNext steps:"
    echo "1. umount -R /mnt"
    echo "2. reboot"
    exit 0
}

# Start script
check_system
main_menu