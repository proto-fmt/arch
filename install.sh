#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Configuration
# -------------------------------
declare -A CONFIG=(
    [DISK]=""
    [ROOT_SIZE]=""
    [SWAP_SIZE]=0
    [HOSTNAME]="archlinux"
    [TIMEZONE]="UTC"
    [LOCALE]="en_US.UTF-8"
    [KEYMAP]="us"
    [USERNAME]=""
    [ADD_SUDO]="yes"
    [FS_TYPE]="btrfs"
    [BOOTLOADER]="grub"
    [MICROCODE]=""
    [GPU_DRIVER]=""
)

declare -r -A COLOR=(
    [RED]=$(tput setaf 1)
    [GREEN]=$(tput setaf 2)
    [YELLOW]=$(tput setaf 3)
    [CYAN]=$(tput setaf 6)
    [NC]=$(tput sgr0)
)

# -------------------------------
# Core Functions
# -------------------------------
die() {
    echo -e "${COLOR[RED]}[FATAL]${COLOR[NC]} $1" >&2
    exit 1
}

print_header() {
    clear
    echo -e "\n${COLOR[GREEN]}Arch Linux Installer${COLOR[NC]}"
    echo -e "=====================\n"
}

format_value() {
    local value="$1"
    [[ -n "$value" ]] && echo -e "${COLOR[GREEN]}$value${COLOR[NC]}" || echo -e "${COLOR[RED]}[NOT SET]${COLOR[NC]}"
}

# -------------------------------
# Interactive Menus
# -------------------------------
main_menu() {
    while true; do
        print_header
        echo -e "${COLOR[CYAN]}Current Configuration:${COLOR[NC]}"
        printf "%-15s: %s\n" "Disk" "$(format_value "${CONFIG[DISK]}")"
        printf "%-15s: %s\n" "Root Size" "$(format_value "${CONFIG[ROOT_SIZE]}G")"
        printf "%-15s: %s\n" "Swap Size" "$(format_value "${CONFIG[SWAP_SIZE]}G")"
        printf "%-15s: %s\n" "Filesystem" "$(format_value "${CONFIG[FS_TYPE]}")"
        printf "%-15s: %s\n" "Hostname" "$(format_value "${CONFIG[HOSTNAME]}")"
        printf "%-15s: %s\n" "Username" "$(format_value "${CONFIG[USERNAME]}")"
        printf "%-15s: %s\n" "Sudo Access" "$(format_value "${CONFIG[ADD_SUDO]}")"
        echo -e "-----------------------------------\n"
        
        echo "1. Select Disk"
        echo "2. Partition Settings"
        echo "3. System Settings"
        echo "4. Install System"
        echo -e "\n0. Exit"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) select_disk ;;
            2) partition_menu ;;
            3) system_menu ;;
            4) install_system ;;
            0) exit 0 ;;
            *) echo -e "${COLOR[RED]}Invalid option!${COLOR[NC]}" && sleep 1 ;;
        esac
    done
}

# -------------------------------
# Disk Selection
# -------------------------------
select_disk() {
    clear
    echo -e "\n${COLOR[GREEN]}Available Disks:${COLOR[NC]}"
    lsblk -d -n -l -o NAME,SIZE,TYPE | grep -v 'rom\|loop\|airoot'
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter disk (e.g. /dev/sda): "${COLOR[NC]})" disk
        if [[ -b "$disk" ]]; then
            CONFIG[DISK]="$disk"
            return
        else
            echo -e "${COLOR[RED]}Invalid disk!${COLOR[NC]}"
        fi
    done
}

# -------------------------------
# Partition Configuration
# -------------------------------
partition_menu() {
    while true; do
        clear
        echo -e "\n${COLOR[GREEN]}Partition Configuration${COLOR[NC]}"
        echo -e "------------------------\n"
        echo "1. Root Size (${COLOR[GREEN]}${CONFIG[ROOT_SIZE]}G${COLOR[NC]})"
        echo "2. Swap Size (${COLOR[GREEN]}${CONFIG[SWAP_SIZE]}G${COLOR[NC]})"
        echo "3. Filesystem Type (${COLOR[GREEN]}${CONFIG[FS_TYPE]}${COLOR[NC]})"
        echo -e "\n0. Back"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) set_size "ROOT_SIZE" "Enter root partition size (GB):" ;;
            2) set_size "SWAP_SIZE" "Enter swap partition size (GB):" ;;
            3) select_filesystem ;;
            0) return ;;
            *) echo -e "${COLOR[RED]}Invalid option!${COLOR[NC]}" && sleep 1 ;;
        esac
    done
}

set_size() {
    local config_key=$1
    local prompt=$2
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"$prompt "${COLOR[NC]})" size
        if [[ "$size" =~ ^[0-9]+$ ]]; then
            CONFIG[$config_key]="$size"
            return
        else
            echo -e "${COLOR[RED]}Invalid size! Must be a number.${COLOR[NC]}"
        fi
    done
}

select_filesystem() {
    clear
    echo -e "\n${COLOR[GREEN]}Select Filesystem Type${COLOR[NC]}"
    echo "1. ext4"
    echo "2. btrfs"
    echo "3. xfs"
    
    read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[FS_TYPE]="ext4" ;;
        2) CONFIG[FS_TYPE]="btrfs" ;;
        3) CONFIG[FS_TYPE]="xfs" ;;
        *) echo -e "${COLOR[RED]}Invalid option!${COLOR[NC]}" ;;
    esac
}

# -------------------------------
# System Configuration
# -------------------------------
system_menu() {
    while true; do
        clear
        echo -e "\n${COLOR[GREEN]}System Settings${COLOR[NC]}"
        echo -e "-------------------\n"
        echo "1. Hostname (${COLOR[GREEN]}${CONFIG[HOSTNAME]}${COLOR[NC]})"
        echo "2. Timezone (${COLOR[REEN]}${CONFIG[TIMEZONE]}${COLOR[NC]})"
        echo "3. Locale (${COLOR[GREEN]}${CONFIG[LOCALE]}${COLOR[NC]})"
        echo "4. Keymap (${COLOR[GREEN]}${CONFIG[KEYMAP]}${COLOR[NC]})"
        echo "5. Username (${COLOR[GREEN]}${CONFIG[USERNAME]}${COLOR[NC]})"
        echo "6. Sudo Access (${COLOR[GREEN]}${CONFIG[ADD_SUDO]}${COLOR[NC]})"
        echo "7. Bootloader (${COLOR[GREEN]}${CONFIG[BOOTLOADER]}${COLOR[NC]})"
        echo -e "\n0. Back"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) set_config_value "HOSTNAME" "Enter hostname:" ;;
            2) set_timezone ;;
            3) set_locale ;;
            4) set_keymap ;;
            5) set_config_value "USERNAME" "Enter username:" ;;
            6) toggle_sudo ;;
            7) select_bootloader ;;
            0) return ;;
            *) echo -e "${COLOR[RED]}Invalid option!${COLOR[NC]}" && sleep 1 ;;
        esac
    done
}

set_config_value() {
    local config_key=$1
    local prompt=$2
    
    read -p "$(echo -e ${COLOR[CYAN]}"$prompt "${COLOR[NC]})" value
    CONFIG[$config_key]="$value"
}

set_timezone() {
    read -p "$(echo -e ${COLOR[CYAN]}"Enter timezone (e.g. Europe/Moscow): "${COLOR[NC]})" tz
    if [[ -f "/usr/share/zoneinfo/$tz" ]]; then
        CONFIG[TIMEZONE]="$tz"
    else
        echo -e "${COLOR[RED]}Invalid timezone!${COLOR[NC]}"
        sleep 1
    fi
}

set_locale() {
    read -p "$(echo -e ${COLOR[CYAN]}"Enter locale (e.g. en_US.UTF-8): "${COLOR[NC]})" locale
    CONFIG[LOCALE]="$locale"
}

set_keymap() {
    read -p "$(echo -e ${COLOR[CYAN]}"Enter keymap (e.g. us, ru): "${COLOR[NC]})" keymap
    CONFIG[KEYMAP]="$keymap"
}

toggle_sudo() {
    CONFIG[ADD_SUDO]=$([ "${CONFIG[ADD_SUDO]}" == "yes" ] && echo "no" || echo "yes")
}

select_bootloader() {
    clear
    echo -e "\n${COLOR[GREEN]}Select Bootloader${COLOR[NC]}"
    echo "1. GRUB"
    echo "2. systemd-boot"
    
    read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[BOOTLOADER]="grub" ;;
        2) CONFIG[BOOTLOADER]="systemd-boot" ;;
        *) echo -e "${COLOR[RED]}Invalid option!${COLOR[NC]}" ;;
    esac
}

# -------------------------------
# Installation Process
# -------------------------------
install_system() {
    check_requirements
    confirm_installation
    detect_hardware
    partition_disk
    install_base
    configure_system
    setup_bootloader
    finalize_installation
}

check_requirements() {
    [[ -b "${CONFIG[DISK]}" ]] || die "Disk not selected!"
    [[ -n "${CONFIG[ROOT_SIZE]}" ]] || die "Root size not set!"
    [[ -d /sys/firmware/efi ]] || die "UEFI not supported"
    command -v pacstrap >/dev/null || die "arch-install-scripts not installed"
}

confirm_installation() {
    echo -e "\n${COLOR[RED]}WARNING: This will erase ALL data on ${CONFIG[DISK]}!${COLOR[NC]}"
    read -p "$(echo -e ${COLOR[CYAN]}"Continue installation? (y/N): "${COLOR[NC]})" confirm
    [[ "$confirm" =~ [yY] ]] || die "Installation aborted"
}

detect_hardware() {
    # Detect CPU microcode
    case $(grep -m1 -oP 'vendor_id\s*:\s*\K.*' /proc/cpuinfo) in
        GenuineIntel) CONFIG[MICROCODE]="intel-ucode" ;;
        AuthenticAMD) CONFIG[MICROCODE]="amd-ucode" ;;
    esac

    # Detect GPU driver
    case $(lspci -nn | grep -i 'vga\|3d\|display') in
        *NVIDIA*) CONFIG[GPU_DRIVER]="nvidia" ;;
        *AMD*)    CONFIG[GPU_DRIVER]="amdgpu" ;;
        *Intel*)  CONFIG[GPU_DRIVER]="i915" ;;
    esac
}

partition_disk() {
    echo -e "\n${COLOR[YELLOW]}Partitioning disk...${COLOR[NC]}"
    parted -s "${CONFIG[DISK]}" mklabel gpt
    parted -s "${CONFIG[DISK]}" mkpart "EFI" fat32 1MiB 513MiB
    parted -s "${CONFIG[DISK]}" set 1 esp on
    parted -s "${CONFIG[DISK]}" mkpart "ROOT" "${CONFIG[FS_TYPE]}" 513MiB "${CONFIG[ROOT_SIZE]}GiB"
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        parted -s "${CONFIG[DISK]}" mkpart "SWAP" linux-swap "${CONFIG[ROOT_SIZE]}GiB" "$((CONFIG[ROOT_SIZE] + CONFIG[SWAP_SIZE]))GiB"
        parted -s "${CONFIG[DISK]}" mkpart "HOME" "${CONFIG[FS_TYPE]}" "$((CONFIG[ROOT_SIZE] + CONFIG[SWAP_SIZE]))GiB" 100%
    else
        parted -s "${CONFIG[DISK]}" mkpart "HOME" "${CONFIG[FS_TYPE]}" "${CONFIG[ROOT_SIZE]}GiB" 100%
    fi

    # Format partitions
    part_prefix=""
    [[ "${CONFIG[DISK]}" =~ nvme ]] && part_prefix="p"
    mkfs.fat -F32 "${CONFIG[DISK]}${part_prefix}1"
    mkfs."${CONFIG[FS_TYPE]}" -f "${CONFIG[DISK]}${part_prefix}2"
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        mkswap "${CONFIG[DISK]}${part_prefix}3"
        swapon "${CONFIG[DISK]}${part_prefix}3"
        mkfs."${CONFIG[FS_TYPE]}" -f "${CONFIG[DISK]}${part_prefix}4"
    else
        mkfs."${CONFIG[FS_TYPE]}" -f "${CONFIG[DISK]}${part_prefix}3"
    fi

    # Mount partitions
    mount "${CONFIG[DISK]}${part_prefix}2" /mnt
    mkdir -p /mnt/{boot,home}
    mount "${CONFIG[DISK]}${part_prefix}1" /mnt/boot
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        mount "${CONFIG[DISK]}${part_prefix}4" /mnt/home
    else
        mount "${CONFIG[DISK]}${part_prefix}3" /mnt/home
    fi
}

install_base() {
    echo -e "\n${COLOR[YELLOW]}Installing base system...${COLOR[NC]}"
    base_packages=(
        base base-devel linux linux-firmware
        networkmanager nano sudo ${CONFIG[MICROCODE]}
        ${CONFIG[GPU_DRIVER]}
    )
    pacstrap /mnt "${base_packages[@]}" || die "Failed to install base system"
    genfstab -U /mnt >> /mnt/etc/fstab || die "Failed to generate fstab"
}

configure_system() {
    echo -e "\n${COLOR[YELLOW]}Configuring system...${COLOR[NC]}"
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CONFIG[TIMEZONE]}" /etc/localtime
    hwclock --systohc
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf
    echo "KEYMAP=${CONFIG[KEYMAP]}" > /etc/vconsole.conf
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname
    sed -i "s/#${CONFIG[LOCALE]}/${CONFIG[LOCALE]}/" /etc/locale.gen
    locale-gen
EOF

    # Create user if specified
    if [[ -n "${CONFIG[USERNAME]}" ]]; then
        arch-chroot /mnt /bin/bash <<EOF
        useradd -m -G wheel -s /bin/bash "${CONFIG[USERNAME]}"
        echo -e "Set password for ${CONFIG[USERNAME]}:"
        passwd "${CONFIG[USERNAME]}"
        if [[ "${CONFIG[ADD_SUDO]}" == "yes" ]]; then
            echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
        fi
EOF
    fi
}

setup_bootloader() {
    echo -e "\n${COLOR[YELLOW]}Installing bootloader...${COLOR[NC]}"
    case "${CONFIG[BOOTLOADER]}" in
        "grub")
            arch-chroot /mnt /bin/bash <<EOF
            pacman -S --noconfirm grub efibootmgr
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
            grub-mkconfig -o /boot/grub/grub.cfg
EOF
            ;;
        "systemd-boot")
            arch-chroot /mnt /bin/bash <<EOF
            bootctl install
            echo "default arch" > /boot/loader/loader.conf
            echo "timeout 3" >> /boot/loader/loader.conf
            echo "title Arch Linux" > /boot/loader/entries/arch.conf
            echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
            echo "initrd /${CONFIG[MICROCODE]}.img" >> /boot/loader/entries/arch.conf
            echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
            echo "options root=PARTUUID=\$(blkid -s PARTUUID -o value ${CONFIG[DISK]}${part_prefix}2) rw" >> /boot/loader/entries/arch.conf
EOF
            ;;
    esac
}

finalize_installation() {
    echo -e "\n${COLOR[GREEN]}Installation complete!${COLOR[NC]}"
    echo -e "Next steps:"
    echo -e "1. umount -R /mnt"
    echo -e "2. reboot"
    exit 0
}

# -------------------------------
# Start the installer
# -------------------------------
main_menu