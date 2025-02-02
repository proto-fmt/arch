#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Colors definitions using tput
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
NC=$(tput sgr0) # No Color

# Initial configuration variables
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
GPU_DRIVER=""
FS_TYPE="ext4"
BOOTLOADER="grub"

# Output helper functions
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
question(){ echo -e "${CYAN}[?]${NC} $1"; }

# Check that all required commands are available
check_dependencies() {
    local commands=("lsblk" "parted" "mkfs.fat" "pacstrap" "arch-chroot" "tput" "ping")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command '$cmd' not found. Please install it before running the script."
            exit 1
        fi
    done
}

# Function for confirming user's choice (yes/no)
confirm() {
    local prompt_message="$1"
    while true; do
        read -r -p "$(question "$prompt_message (y/N): ")" response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            [nN][oO]|[nN]|'') return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Check for root privileges and UEFI system
check_system() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root!"
        exit 1
    fi
    if [[ ! -d /sys/firmware/efi ]]; then
        error "This script only works with UEFI systems!"
        exit 1
    fi
}

# Check internet connection
check_internet() {
    info "Checking internet connection..."
    if ! ping -c 1 archlinux.org &>/dev/null; then
        error "No internet connection detected! Please connect and try again."
        exit 1
    fi
}

# Detect hardware (CPU microcode and GPU driver)
detect_hardware() {
    # CPU microcode
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        MICROCODE="intel-ucode"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        MICROCODE="amd-ucode"
    fi

    # GPU driver
    if lspci | grep -qi "NVIDIA"; then
        GPU_DRIVER="nvidia"
    elif lspci | grep -qi "AMD"; then
        GPU_DRIVER="amd"
    elif lspci | grep -qi "Intel"; then
        GPU_DRIVER="intel"
    fi
}

# Main interactive menu
main_menu() {
    while true; do
        clear
        echo -e "\n${GREEN}Arch Linux UEFI Installer${NC}"
        echo -e "=========================\n"
        echo "1. Disk (${DISK:+${GREEN}${DISK}${NC}}${DISK:-${YELLOW}[ EMPTY ]${NC}})"
        echo "2. Partition Configuration"
        echo "3. System Settings"
        echo "4. Start Installation"
        echo -e "\n0. Exit"
        
        read -r -p "$(question "Enter your choice: ")" choice
        case $choice in
            1) select_disk ;;
            2) partition_menu ;;
            3) system_settings_menu ;;
            4) start_installation ;;
            0) exit 0 ;;
            *) warning "Invalid option!"; sleep 1 ;;
        esac
    done
}

# Disk selection function
select_disk() {
    clear
    echo -e "\n${GREEN}Available disks:${NC}"
    lsblk -d -n -l -o NAME,SIZE,TYPE | grep -v 'loop\|rom'
    
    read -r -p "$(question "Enter disk device (e.g. /dev/sda): ")" input_disk
    if [[ -b "$input_disk" ]]; then
        DISK="$input_disk"
    else
        warning "Invalid disk device!"
        DISK=""
        sleep 1
    fi
}

# Partition configuration menu
partition_menu() {
    while true; do
        clear
        echo -e "\n${GREEN}Partition Configuration${NC}"
        echo -e "=========================\n"
        echo "1. Root Size (${ROOT_SIZE:+${GREEN}${ROOT_SIZE}GB${NC}}${ROOT_SIZE:-${YELLOW}[ EMPTY ]${NC}})"
        echo "2. Swap Size (${SWAP_SIZE:+${GREEN}${SWAP_SIZE}GB${NC}}${SWAP_SIZE:-${YELLOW}[ EMPTY ]${NC}})"
        echo "3. Home Size (${HOME_SIZE:+${GREEN}${HOME_SIZE}GB${NC}}${HOME_SIZE:-${YELLOW}[ Remaining space ]${NC}})"
        echo "4. Filesystem Type (${FS_TYPE:+${GREEN}${FS_TYPE}${NC}})"
        echo -e "\n0. Back"
        
        read -r -p "$(question "Enter your choice: ")" choice
        case $choice in
            1) set_root_size ;;
            2) set_swap_size ;;
            3) set_home_size ;;
            4) set_filesystem ;;
            0) break ;;
            *) warning "Invalid option!"; sleep 1 ;;
        esac
    done
}

# Set filesystem type
set_filesystem() {
    clear
    echo -e "\n${GREEN}Select Filesystem Type${NC}"
    echo "1. ext4 (default)"
    echo "2. btrfs"
    echo "3. xfs"
    
    read -r -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) FS_TYPE="ext4" ;;
        2) FS_TYPE="btrfs" ;;
        3) FS_TYPE="xfs" ;;
        *) warning "Invalid option! Using default ext4."; FS_TYPE="ext4" ;;
    esac
}

# Set partition sizes
set_root_size() {
    read -r -p "$(question "Enter root partition size in GB: ")" size
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ]; then
        ROOT_SIZE=$size
    else
        warning "Invalid size! Please enter a positive number."
        sleep 1
    fi
}

set_swap_size() {
    read -r -p "$(question "Enter swap partition size in GB (0 for no swap): ")" size
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -ge 0 ]; then
        SWAP_SIZE=$size
    else
        warning "Invalid size! Please enter a non-negative number."
        sleep 1
    fi
}

set_home_size() {
    read -r -p "$(question "Enter home partition size in GB (leave empty for remaining space): ")" size
    if [[ -z "$size" ]] || ([[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ]); then
        HOME_SIZE=$size
    else
        warning "Invalid size! Please enter a positive number or leave empty."
        sleep 1
    fi
}

# System settings menu
system_settings_menu() {
    while true; do
        clear
        echo -e "\n${GREEN}System Settings${NC}"
        echo -e "================\n"
        echo "1. Hostname (${HOSTNAME:+${GREEN}${HOSTNAME}${NC}})"
        echo "2. Timezone (${TIMEZONE:+${GREEN}${TIMEZONE}${NC}})"
        echo "3. Locale (${LOCALE:+${GREEN}${LOCALE}${NC}})"
        echo "4. Keymap (${KEYMAP:+${GREEN}${KEYMAP}${NC}})"
        echo "5. Username (${USERNAME:+${GREEN}${USERNAME}${NC}})"
        echo "6. Bootloader (${BOOTLOADER:+${GREEN}${BOOTLOADER}${NC}})"
        echo -e "\n0. Back"
        
        read -r -p "$(question "Enter your choice: ")" choice
        case $choice in
            1) read -r -p "$(question "Enter hostname: ")" HOSTNAME ;;
            2) read -r -p "$(question "Enter timezone (e.g. Europe/London): ")" TIMEZONE ;;
            3) read -r -p "$(question "Enter locale (e.g. en_US.UTF-8): ")" LOCALE ;;
            4) read -r -p "$(question "Enter keymap (e.g. us): ")" KEYMAP ;;
            5) read -r -p "$(question "Enter username: ")" USERNAME ;;
            6) set_bootloader ;;
            0) break ;;
            *) warning "Invalid option!"; sleep 1 ;;
        esac
    done
}

# Set bootloader selection
set_bootloader() {
    clear
    echo -e "\n${GREEN}Select Bootloader${NC}"
    echo "1. GRUB"
    echo "2. systemd-boot"
    
    read -r -p "$(question "Enter your choice: ")" choice
    case $choice in
        1) BOOTLOADER="grub" ;;
        2) BOOTLOADER="systemd-boot" ;;
        *) warning "Invalid option! Using default (GRUB)"; BOOTLOADER="grub" ;;
    esac
}

# Installation process
start_installation() {
    clear
    # Validate required configuration
    if [[ -z "$DISK" ]]; then
        error "Disk not selected!"
        sleep 2
        return
    fi
    if [[ -z "$ROOT_SIZE" ]]; then
        error "Root size not configured!"
        sleep 2
        return
    fi

    check_internet
    check_dependencies

    info "WARNING: This will erase all data on ${DISK}!"
    if ! confirm "Are you sure you want to continue?"; then
        main_menu
        return
    fi

    detect_hardware

    # Determine partition prefix for NVMe disks
    local PART_PREFIX=""
    if [[ "$DISK" =~ nvme ]]; then
        PART_PREFIX="p"
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

    # Install GPU drivers if detected
    case $GPU_DRIVER in
        nvidia) pacstrap /mnt nvidia nvidia-utils nvidia-settings ;;
        amd) pacstrap /mnt xf86-video-amdgpu ;;
        intel) pacstrap /mnt xf86-video-intel ;;
    esac

    # Install bootloader packages
    case $BOOTLOADER in
        grub) pacstrap /mnt grub efibootmgr ;;
        systemd-boot) pacstrap /mnt efibootmgr ;;
    esac

    # Generate fstab
    info "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    # Configure system using chroot
    info "Configuring system..."
    arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname
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
        echo "options root=UUID=\$(blkid -s UUID -o value ${DISK}${PART_PREFIX}2) rw" >> /boot/loader/entries/arch.conf
        ;;
esac

# Set root password
echo "Set root password:"
passwd

# Create additional user if username specified
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

# Start the installation script
check_system
main_menu