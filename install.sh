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

# Output functions
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
question() { echo -e "${CYAN}[?]${NC} $1"; }

# Check root privileges
check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root!"
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
    echo -e "\n${GREEN}Arch Linux Installer${NC}"
    echo -e "=======================\n"
    echo "1. Select Disk (${GREEN}${DISK}${NC})"
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
    echo "1. Root Size (${GREEN}${ROOT_SIZE}GB${NC})"
    echo "2. Swap Size (${GREEN}${SWAP_SIZE}GB${NC})"
    echo "3. Home Size (${GREEN}${HOME_SIZE:-"Remaining space"}${NC})"
    echo "4. Filesystem Type (${GREEN}${FS_TYPE}${NC})"
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

# System settings menu
system_settings_menu() {
    clear
    echo -e "\n${GREEN}System Settings${NC}"
    echo -e "================\n"
    echo "1. Hostname (${GREEN}${HOSTNAME}${NC})"
    echo "2. Timezone (${GREEN}${TIMEZONE}${NC})"
    echo "3. Locale (${GREEN}${LOCALE}${NC})"
    echo "4. Keymap (${GREEN}${KEYMAP}${NC})"
    echo "5. Username (${GREEN}${USERNAME}${NC})"
    echo -e "\n0. Back"
    
    read -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) set_hostname;;
        2) set_timezone;;
        3) set_locale;;
        4) set_keymap;;
        5) set_username;;
        0) main_menu;;
        *) warning "Invalid option!"; sleep 1; system_settings_menu;;
    esac
}

# Installation process
start_installation() {
    clear
    [[ -z "$DISK" ]] && error "Disk not selected!"
    [[ -z "$ROOT_SIZE" ]] && error "Root size not configured!"

    echo -e "\n${RED}WARNING: This will erase all data on ${DISK}!${NC}"
    read -p "$(question "Are you sure you want to continue? (y/N): ")" confirm
    [[ "$confirm" =~ [yY] ]] || main_menu

    # Detect hardware
    detect_hardware

    # Partitioning
    info "Partitioning disk..."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart "EFI" fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart "ROOT" $FS_TYPE 513MiB "$((ROOT_SIZE + 513))"MiB
    [[ $SWAP_SIZE -gt 0 ]] && parted -s "$DISK" mkpart "SWAP" linux-swap "$((ROOT_SIZE + 513))"MiB "$((ROOT_SIZE + SWAP_SIZE + 513))"MiB
    parted -s "$DISK" mkpart "HOME" $FS_TYPE "$([[ $SWAP_SIZE -gt 0 ]] && echo "$((ROOT_SIZE + SWAP_SIZE + 513))" || echo "$((ROOT_SIZE + 513))")"MiB 100%

    # Formatting
    info "Formatting partitions..."
    mkfs.fat -F32 "${DISK}1"
    mkfs.${FS_TYPE} "${DISK}2"
    [[ $SWAP_SIZE -gt 0 ]] && mkswap "${DISK}3" && swapon "${DISK}3"
    mkfs.${FS_TYPE} "${DISK}$([[ $SWAP_SIZE -gt 0 ]] && echo "4" || echo "3")"

    # Mounting
    info "Mounting filesystems..."
    mount "${DISK}2" /mnt
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi
    mkdir -p /mnt/home
    mount "${DISK}$([[ $SWAP_SIZE -gt 0 ]] && echo "4" || echo "3")" /mnt/home

    # Base installation
    info "Installing base system..."
    pacstrap /mnt base base-devel linux linux-firmware linux-headers $MICROCODE \
        grub efibootmgr networkmanager nano sudo

    # GPU drivers
    case $GPU_DRIVER in
        nvidia) pacstrap /mnt nvidia nvidia-utils nvidia-settings;;
        amd) pacstrap /mnt xf86-video-amdgpu;;
        intel) pacstrap /mnt xf86-video-intel;;
    esac

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # System configuration
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
    
    # Bootloader
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Root password
    echo "Set root password:"
    passwd

    # User account
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

# Initial checks
check_root
main_menu