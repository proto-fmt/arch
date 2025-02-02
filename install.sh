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
    [HOME_SIZE]=""
    [HOSTNAME]="archlinux"
    [TIMEZONE]="UTC"
    [LOCALE]="en_US.UTF-8"
    [KEYMAP]="us"
    [USERNAME]=""
    [ADD_SUDO]="yes"
    [MICROCODE]=""
    [GPU_DRIVER]=""
    [FS_TYPE]="btrfs"
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
# Utility Functions
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

print_status() {
    echo -e "${COLOR[CYAN]}Current Configuration:${COLOR[NC]}"
    printf "%-12s: %s\n" "Disk" "$(format_value "${CONFIG[DISK]}")"
    printf "%-12s: %s\n" "Root Size" "$(format_value "${CONFIG[ROOT_SIZE]}G")"
    printf "%-12s: %s\n" "Swap Size" "$(format_value "${CONFIG[SWAP_SIZE]}G")"
    printf "%-12s: %s\n" "Filesystem" "$(format_value "${CONFIG[FS_TYPE]}")"
    printf "%-12s: %s\n" "Hostname" "$(format_value "${CONFIG[HOSTNAME]}")"
    echo -e "------------------------------"
}

format_value() {
    [[ -n "$1" ]] && echo -e "${COLOR[GREEN]}$1${COLOR[NC]}" || echo -e "${COLOR[RED]}[NOT SET]${COLOR[NC]}"
}

# -------------------------------
# Validation Functions
# -------------------------------
validate_disk() {
    [[ -b "${CONFIG[DISK]}" ]] || die "Invalid disk: ${CONFIG[DISK]}"
}

validate_size() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 0 )) || die "Invalid size: $1"
}

# -------------------------------
# System Checks
# -------------------------------
check_dependencies() {
    local deps=("lsblk" "parted" "mkfs.fat" "pacstrap" "arch-chroot")
    for cmd in "${deps[@]}"; do
        command -v "$cmd" >/dev/null || die "Missing required: $cmd"
    done
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || die "UEFI not supported"
}

check_network() {
    ping -c 1 archlinux.org >/dev/null || die "No internet connection"
}

# -------------------------------
# Hardware Detection
# -------------------------------
detect_cpu() {
    case $(grep -m1 -oP 'vendor_id\s*:\s*\K.*' /proc/cpuinfo) in
        GenuineIntel) CONFIG[MICROCODE]="intel-ucode" ;;
        AuthenticAMD) CONFIG[MICROCODE]="amd-ucode" ;;
    esac
}

detect_gpu() {
    case $(lspci -nn | grep -i 'vga\|3d\|display') in
        *NVIDIA*) CONFIG[GPU_DRIVER]="nvidia" ;;
        *AMD*)    CONFIG[GPU_DRIVER]="amdgpu" ;;
        *Intel*)  CONFIG[GPU_DRIVER]="i915" ;;
    esac
}

# -------------------------------
# Partitioning Functions
# -------------------------------
calculate_partitions() {
    local part_prefix=""
    [[ "${CONFIG[DISK]}" =~ nvme ]] && part_prefix="p"
    
    CONFIG[EFI_PART]="${CONFIG[DISK]}${part_prefix}1"
    CONFIG[ROOT_PART]="${CONFIG[DISK]}${part_prefix}2"
    CONFIG[SWAP_PART]="${CONFIG[DISK]}${part_prefix}3"
    CONFIG[HOME_PART]="${CONFIG[DISK]}${part_prefix}4"
}

create_partitions() {
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
}

format_partitions() {
    mkfs.fat -F32 "${CONFIG[EFI_PART]}"
    mkfs."${CONFIG[FS_TYPE]}" -f "${CONFIG[ROOT_PART]}"
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        mkswap "${CONFIG[SWAP_PART]}"
        swapon "${CONFIG[SWAP_PART]}"
    fi
    
    mkfs."${CONFIG[FS_TYPE]}" -f "${CONFIG[HOME_PART]}"
}

mount_filesystems() {
    mount "${CONFIG[ROOT_PART]}" /mnt
    mkdir -p /mnt/{boot,home}
    mount "${CONFIG[EFI_PART]}" /mnt/boot
    mount "${CONFIG[HOME_PART]}" /mnt/home
}

# -------------------------------
# Installation Functions
# -------------------------------
install_base() {
    local base_pkgs=("base" "base-devel" "linux" "linux-firmware" "networkmanager")
    pacstrap /mnt "${base_pkgs[@]}" "${CONFIG[MICROCODE]}" || die "Base install failed"
}

configure_fstab() {
    genfstab -U /mnt >> /mnt/etc/fstab || die "Fstab generation failed"
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CONFIG[TIMEZONE]}" /etc/localtime
    hwclock --systohc
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf
    echo "KEYMAP=${CONFIG[KEYMAP]}" > /etc/vconsole.conf
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname
    systemctl enable NetworkManager
EOF
}

# -------------------------------
# Main Execution Flow
# -------------------------------
main() {
    trap 'die "Aborted by user"' INT
    check_dependencies
    check_uefi
    check_network
    
    detect_cpu
    detect_gpu
    
    validate_disk
    calculate_partitions
    create_partitions
    format_partitions
    mount_filesystems
    install_base
    configure_fstab
    configure_system
    
    echo -e "\n${COLOR[GREEN]}Installation complete!${COLOR[NC]}"
    echo -e "Next steps:"
    echo -e "1. umount -R /mnt"
    echo -e "2. reboot"
}

main "$@"