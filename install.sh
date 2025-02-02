#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Global Configuration
# -------------------------------
declare -A CONFIG=(
    [DISK]=""
    [ROOT_SIZE]="20"
    [HOME_SIZE]="10"
    [SWAP_SIZE]="2"
    [UEFI_SIZE]="512"
    [FS_TYPE]="btrfs"
    [HOSTNAME]="archlinux"
    [TIMEZONE]="UTC"
    [LOCALE]="en_US.UTF-8"
    [KEYMAP]="us"
    [USERNAME]="user"
    [ADD_SUDO]="yes"
    [MICROCODE]="auto"
    [GPU_DRIVER]="auto"
    [BOOTLOADER]="grub"
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
    echo -e "${COLOR[RED]}[ERROR]${COLOR[NC]} $1" >&2
    exit 1
}

print_header() {
    clear
    echo -e "\n${COLOR[GREEN]}Arch Linux Installer${COLOR[NC]}"
    echo -e "=====================\n"
}

format_value() {
    local value="$1"
    if [[ -n "$value" ]]; then
        echo -e "${COLOR[GREEN]}${value}${COLOR[NC]}"
    else
        echo -e "${COLOR[RED]}[NOT SET]${COLOR[NC]}"
    fi
}

# -------------------------------
# Validation Functions
# -------------------------------
check_uefi() {
    [[ -d /sys/firmware/efi/efivars ]] || die "UEFI mode not enabled"
}

check_disk_space() {
    local disk="${CONFIG[DISK]}"
    [[ -b "$disk" ]] || die "Invalid disk: $disk"

    local total_needed=$(( 
        CONFIG[UEFI_SIZE] + 
        (CONFIG[ROOT_SIZE] + CONFIG[HOME_SIZE] + CONFIG[SWAP_SIZE]) * 1024 
    ))

    local disk_size_mb=$(blockdev --getsize64 "$disk" | awk '{printf "%d", $1/1024/1024}')
    
    (( total_needed > disk_size_mb )) && die "Not enough disk space! Needed: ${total_needed}MB, Available: ${disk_size_mb}MB"
}

# -------------------------------
# Configuration Menus
# -------------------------------
main_menu() {
    while true; do
        print_header
        echo "1. Disk & Partitions"
        echo "2. System Settings"
        echo "3. Hardware Settings"
        echo "4. Review Configuration"
        echo "5. Start Installation"
        echo -e "\n0. Exit"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) disk_menu ;;
            2) system_menu ;;
            3) hardware_menu ;;
            4) review_config ;;
            5) install_system ;;
            0) exit 0 ;;
            *) die "Invalid option" ;;
        esac
    done
}

disk_menu() {
    while true; do
        print_header
        echo -e "Disk Configuration\n"
        echo "1. Select disk ($(format_value "${CONFIG[DISK]}"))"
        echo "2. Root partition size ($(format_value "${CONFIG[ROOT_SIZE]}G"))"
        echo "3. Home partition size ($(format_value "${CONFIG[HOME_SIZE]}G"))"
        echo "4. Swap size ($(format_value "${CONFIG[SWAP_SIZE]}G"))"
        echo "5. UEFI partition size ($(format_value "${CONFIG[UEFI_SIZE]}M"))"
        echo "6. Filesystem type ($(format_value "${CONFIG[FS_TYPE]}"))"
        echo -e "\n0. Back"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) select_disk ;;
            2) set_config "ROOT_SIZE" "Enter root partition size (GB): " ;;
            3) set_config "HOME_SIZE" "Enter home partition size (GB): " ;;
            4) set_config "SWAP_SIZE" "Enter swap size (GB): " ;;
            5) set_uefi_size ;;
            6) select_filesystem ;;
            0) return ;;
            *) die "Invalid option" ;;
        esac
    done
}

system_menu() {
    while true; do
        print_header
        echo -e "System Settings\n"
        echo "1. Hostname ($(format_value "${CONFIG[HOSTNAME]}"))"
        echo "2. Timezone ($(format_value "${CONFIG[TIMEZONE]}"))"
        echo "3. Locale ($(format_value "${CONFIG[LOCALE]}"))"
        echo "4. Keymap ($(format_value "${CONFIG[KEYMAP]}"))"
        echo "5. Username ($(format_value "${CONFIG[USERNAME]}"))"
        echo "6. Sudo Access ($(format_value "${CONFIG[ADD_SUDO]}"))"
        echo -e "\n0. Back"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) set_config "HOSTNAME" "Enter hostname: " ;;
            2) set_timezone ;;
            3) set_locale ;;
            4) set_keymap ;;
            5) set_config "USERNAME" "Enter username: " ;;
            6) toggle_sudo ;;
            0) return ;;
            *) die "Invalid option" ;;
        esac
    done
}

hardware_menu() {
    while true; do
        print_header
        echo -e "Hardware Settings\n"
        echo "1. CPU microcode ($(format_value "${CONFIG[MICROCODE]}"))"
        echo "2. GPU driver ($(format_value "${CONFIG[GPU_DRIVER]}"))"
        echo "3. Bootloader ($(format_value "${CONFIG[BOOTLOADER]}"))"
        echo -e "\n0. Back"
        
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter choice: "${COLOR[NC]})" choice
        case $choice in
            1) set_microcode ;;
            2) set_gpu_driver ;;
            3) set_bootloader ;;
            0) return ;;
            *) die "Invalid option" ;;
        esac
    done
}

# -------------------------------
# Configuration Setters
# -------------------------------
select_disk() {
    print_header
    echo -e "Available disks:\n"
    lsblk -d -n -l -o NAME,SIZE,TYPE | grep -v 'rom\|loop\|airoot'
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter disk (e.g. /dev/sda): "${COLOR[NC]})" disk
        [[ -b "$disk" ]] && { CONFIG[DISK]="$disk"; return; }
        die "Invalid disk: $disk"
    done
}

set_config() {
    local key="$1"
    local prompt="$2"
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"$prompt"${COLOR[NC]})" value
        [[ "$value" =~ ^[0-9]+$ ]] && { CONFIG[$key]="$value"; return; }
        die "Invalid input. Numbers only."
    done
}

set_uefi_size() {
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"Enter UEFI size (MB, min 512): "${COLOR[NC]})" size
        [[ "$size" =~ ^[0-9]+$ ]] && (( size >= 512 )) && { CONFIG[UEFI_SIZE]="$size"; return; }
        die "Invalid size. Minimum 512MB."
    done
}

select_filesystem() {
    echo -e "\n1. btrfs\n2. ext4"
    read -p "$(echo -e ${COLOR[CYAN]}"Select filesystem: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[FS_TYPE]="btrfs" ;;
        2) CONFIG[FS_TYPE]="ext4" ;;
        *) die "Invalid selection" ;;
    esac
}

set_timezone() {
    print_header
    echo -e "Available timezones:\n"
    timedatectl list-timezones | head -n 20
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter timezone (e.g. Europe/London): "${COLOR[NC]})" tz
        [[ -f "/usr/share/zoneinfo/$tz" ]] && { CONFIG[TIMEZONE]="$tz"; return; }
        die "Invalid timezone"
    done
}

set_microcode() {
    detect_microcode
    echo -e "\nCurrent CPU: ${COLOR[YELLOW]}${CONFIG[MICROCODE]}${COLOR[NC]}"
    echo -e "1. Auto-detected\n2. Intel\n3. AMD"
    read -p "$(echo -e ${COLOR[CYAN]}"Select microcode: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[MICROCODE]="auto" ;;
        2) CONFIG[MICROCODE]="intel" ;;
        3) CONFIG[MICROCODE]="amd" ;;
        *) die "Invalid selection" ;;
    esac
}

detect_microcode() {
    local vendor=$(grep -m1 -oP 'vendor_id\s*:\s*\K.*' /proc/cpuinfo)
    [[ "$vendor" == *Intel* ]] && CONFIG[MICROCODE]="intel"
    [[ "$vendor" == *AMD* ]] && CONFIG[MICROCODE]="amd"
}

set_gpu_driver() {
    detect_gpu
    echo -e "\nDetected GPU: ${COLOR[YELLOW]}${CONFIG[GPU_DRIVER]}${COLOR[NC]}"
    echo -e "1. Auto-detected\n2. NVIDIA\n3. AMD\n4. Intel"
    read -p "$(echo -e ${COLOR[CYAN]}"Select GPU driver: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[GPU_DRIVER]="auto" ;;
        2) CONFIG[GPU_DRIVER]="nvidia" ;;
        3) CONFIG[GPU_DRIVER]="amdgpu" ;;
        4) CONFIG[GPU_DRIVER]="i915" ;;
        *) die "Invalid selection" ;;
    esac
}

detect_gpu() {
    local gpu=$(lspci -nn | grep -i 'vga\|3d\|display')
    [[ "$gpu" == *NVIDIA* ]] && CONFIG[GPU_DRIVER]="nvidia"
    [[ "$gpu" == *AMD* ]] && CONFIG[GPU_DRIVER]="amdgpu"
    [[ "$gpu" == *Intel* ]] && CONFIG[GPU_DRIVER]="i915"
}

set_bootloader() {
    echo -e "\n1. GRUB\n2. systemd-boot"
    read -p "$(echo -e ${COLOR[CYAN]}"Select bootloader: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[BOOTLOADER]="grub" ;;
        2) CONFIG[BOOTLOADER]="systemd-boot" ;;
        *) die "Invalid selection" ;;
    esac
}

toggle_sudo() {
    CONFIG[ADD_SUDO]=$([ "${CONFIG[ADD_SUDO]}" == "yes" ] && echo "no" || echo "yes")
}

set_locale() {
    print_header
    echo -e "Available locales:\n"
    grep -E '^#?[a-z].*UTF-8' /etc/locale.gen | cut -d' ' -f1
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter locale (e.g. en_US.UTF-8): "${COLOR[NC]})" locale
        grep -q "^#\?${locale} " /etc/locale.gen && { CONFIG[LOCALE]="$locale"; return; }
        die "Invalid locale"
    done
}

set_keymap() {
    print_header
    echo -e "Available keymaps:\n"
    localectl list-keymaps | head -n 20
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter keymap (e.g. us, ru): "${COLOR[NC]})" keymap
        localectl list-keymaps | grep -qx "$keymap" && { CONFIG[KEYMAP]="$keymap"; return; }
        die "Invalid keymap"
    done
}

# -------------------------------
# Installation Process
# -------------------------------
install_system() {
    print_header
    check_disk_space
    confirm_installation
    
    echo -e "\n${COLOR[YELLOW]}Starting installation...${COLOR[NC]}"
    trap cleanup EXIT INT TERM
    
    partition_disk
    format_partitions
    mount_filesystems
    install_base
    configure_system
    setup_bootloader
    
    echo -e "\n${COLOR[GREEN]}Installation complete!${COLOR[NC]}"
    echo -e "Next steps:"
    echo -e "1. umount -R /mnt"
    echo -e "2. reboot"
    exit 0
}

confirm_installation() {
    echo -e "\n${COLOR[RED]}WARNING: This will erase ALL data on ${CONFIG[DISK]}!${COLOR[NC]}"
    read -p "$(echo -e ${COLOR[CYAN]}"Continue installation? (y/N): "${COLOR[NC]})" confirm
    [[ "$confirm" =~ [yY] ]] || die "Installation aborted"
}

cleanup() {
    echo -e "\n${COLOR[RED]}Cleaning up...${COLOR[NC]}"
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true
}

partition_disk() {
    echo -e "\n${COLOR[YELLOW]}Partitioning disk...${COLOR[NC]}"
    parted -s "${CONFIG[DISK]}" mklabel gpt
    parted -s "${CONFIG[DISK]}" mkpart "EFI" fat32 1MiB "${CONFIG[UEFI_SIZE]}MiB"
    parted -s "${CONFIG[DISK]}" set 1 esp on
    parted -s "${CONFIG[DISK]}" mkpart "ROOT" "${CONFIG[FS_TYPE]}" "${CONFIG[UEFI_SIZE]}MiB" "$((CONFIG[UEFI_SIZE] + CONFIG[ROOT_SIZE] * 1024))MiB"
    
    local next_start="$((CONFIG[UEFI_SIZE] + CONFIG[ROOT_SIZE] * 1024))MiB"
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        parted -s "${CONFIG[DISK]}" mkpart "SWAP" linux-swap "$next_start" "$((next_start + CONFIG[SWAP_SIZE] * 1024))MiB"
        next_start="$((next_start + CONFIG[SWAP_SIZE] * 1024))MiB"
    fi
    
    parted -s "${CONFIG[DISK]}" mkpart "HOME" "${CONFIG[FS_TYPE]}" "$next_start" 100%
}

format_partitions() {
    echo -e "\n${COLOR[YELLOW]}Formatting partitions...${COLOR[NC]}"
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
}

mount_filesystems() {
    echo -e "\n${COLOR[YELLOW]}Mounting filesystems...${COLOR[NC]}"
    part_prefix=""
    [[ "${CONFIG[DISK]}" =~ nvme ]] && part_prefix="p"
    
    mount "${CONFIG[DISK]}${part_prefix}2" /mnt
    mkdir -p /mnt/boot
    mount "${CONFIG[DISK]}${part_prefix}1" /mnt/boot
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        mkdir -p /mnt/home
        mount "${CONFIG[DISK]}${part_prefix}4" /mnt/home
    else
        mkdir -p /mnt/home
        mount "${CONFIG[DISK]}${part_prefix}3" /mnt/home
    fi
}

install_base() {
    echo -e "\n${COLOR[YELLOW]}Installing base system...${COLOR[NC]}"
    local microcode=""
    [[ "${CONFIG[MICROCODE]}" != "auto" ]] && microcode="${CONFIG[MICROCODE]}-ucode"
    
    base_packages=(
        base base-devel linux linux-firmware
        networkmanager nano sudo $microcode
        "${CONFIG[GPU_DRIVER]}"
    )
    
    pacstrap /mnt "${base_packages[@]}" || die "Failed to install base system"
}

configure_system() {
    echo -e "\n${COLOR[YELLOW]}Configuring system...${COLOR[NC]}"
    genfstab -U /mnt >> /mnt/etc/fstab || die "Failed to generate fstab"
    
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CONFIG[TIMEZONE]}" /etc/localtime
    hwclock --systohc
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf
    echo "KEYMAP=${CONFIG[KEYMAP]}" > /etc/vconsole.conf
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname
    sed -i "s/#${CONFIG[LOCALE]}/${CONFIG[LOCALE]}/" /etc/locale.gen
    locale-gen
    
    if [[ -n "${CONFIG[USERNAME]}" ]]; then
        useradd -m -G wheel -s /bin/bash "${CONFIG[USERNAME]}"
        echo -e "Set password for ${CONFIG[USERNAME]}:"
        passwd "${CONFIG[USERNAME]}"
        [[ "${CONFIG[ADD_SUDO]}" == "yes" ]] && echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    fi
    
    systemctl enable NetworkManager
EOF
}

setup_bootloader() {
    echo -e "\n${COLOR[YELLOW]}Installing bootloader...${COLOR[NC]}"
    part_prefix=""
    [[ "${CONFIG[DISK]}" =~ nvme ]] && part_prefix="p"
    
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

review_config() {
    print_header
    echo -e "${COLOR[CYAN]}Current Configuration:${COLOR[NC]}"
    printf "%-15s: %s\n" "Disk" "$(format_value "${CONFIG[DISK]}")"
    printf "%-15s: %s\n" "Root Size" "$(format_value "${CONFIG[ROOT_SIZE]}G")"
    printf "%-15s: %s\n" "Home Size" "$(format_value "${CONFIG[HOME_SIZE]}G")"
    printf "%-15s: %s\n" "Swap Size" "$(format_value "${CONFIG[SWAP_SIZE]}G")"
    printf "%-15s: %s\n" "UEFI Size" "$(format_value "${CONFIG[UEFI_SIZE]}M")"
    printf "%-15s: %s\n" "Filesystem" "$(format_value "${CONFIG[FS_TYPE]}")"
    printf "%-15s: %s\n" "Hostname" "$(format_value "${CONFIG[HOSTNAME]}")"
    printf "%-15s: %s\n" "Timezone" "$(format_value "${CONFIG[TIMEZONE]}")"
    printf "%-15s: %s\n" "Locale" "$(format_value "${CONFIG[LOCALE]}")"
    printf "%-15s: %s\n" "Keymap" "$(format_value "${CONFIG[KEYMAP]}")"
    printf "%-15s: %s\n" "Username" "$(format_value "${CONFIG[USERNAME]}")"
    printf "%-15s: %s\n" "Sudo Access" "$(format_value "${CONFIG[ADD_SUDO]}")"
    printf "%-15s: %s\n" "Microcode" "$(format_value "${CONFIG[MICROCODE]}")"
    printf "%-15s: %s\n" "GPU Driver" "$(format_value "${CONFIG[GPU_DRIVER]}")"
    printf "%-15s: %s\n" "Bootloader" "$(format_value "${CONFIG[BOOTLOADER]}")"
    read -p "$(echo -e ${COLOR[CYAN]}"\nPress Enter to return..."${COLOR[NC]})"
}

# -------------------------------
# Start the installer
# -------------------------------
check_uefi
main_menu