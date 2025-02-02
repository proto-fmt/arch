#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Global Configuration
# -------------------------------
declare -A CONFIG=(
    [DISK]=""                   # Disk path (e.g. /dev/sda)
    [DISK_SIZE]=""              # Disk size in GB
    [ROOT_SIZE]="20"            # Root partition size in GB
    [HOME_SIZE]="10"            # Home partition size in GB
    [SWAP_SIZE]="0"             # Swap size in GB (0 to disable)
    [HOSTNAME]="archlinux"      # System hostname
    [TIMEZONE]="UTC"            # Timezone
    [LOCALE]="en_US.UTF-8"      # System locale
    [KEYMAP]="us"               # Keyboard layout
    [USERNAME]=""               # Primary user name
    [ADD_SUDO]="yes"            # Enable sudo access (yes/no)
    [MICROCODE]="auto"          # CPU microcode (auto/intel/amd)
    [GPU_DRIVER]="auto"         # GPU driver (auto/nvidia/amdgpu/i915)
    [BOOTLOADER]="grub"         # Bootloader (grub/systemd-boot)
)

declare -r -A COLOR=(
    [RED]=$(tput setaf 1)
    [GREEN]=$(tput setaf 2)
    [YELLOW]=$(tput setaf 3)
    [CYAN]=$(tput setaf 6)
    [NC]=$(tput sgr0)
)

# Fixed installation parameters
declare -r UEFI_SIZE=1024       # 1GB UEFI partition
declare -r FS_TYPE="ext4"       # Filesystem type

# Detected hardware information
declare -A DETECTED=(
    [MICROCODE]=""
    [GPU_DRIVER]=""
)

# -------------------------------
# Validation Functions
# -------------------------------
validate_disk() {
    [[ -b "$1" ]] && return 0 || return 1
}

validate_size() {
    [[ "$1" =~ ^[0-9]+$ ]] && return 0 || return 1
}

validate_hostname() {
    [[ "$1" =~ ^[a-zA-Z0-9\-]{1,63}$ ]] && return 0 || return 1
}

validate_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] && return 0 || return 1
}

validate_timezone() {
    [[ -f "/usr/share/zoneinfo/$1" ]] && return 0 || return 1
}

validate_locale() {
    grep -q "^#\?$1 " /etc/locale.gen && return 0 || return 1
}

validate_keymap() {
    localectl list-keymaps | grep -qx "$1" && return 0 || return 1
}

validate_disk_space() {
    local total=$(( UEFI_SIZE + CONFIG[ROOT_SIZE] + CONFIG[HOME_SIZE] + CONFIG[SWAP_SIZE] ))
    (( total <= CONFIG[DISK_SIZE] )) && return 0 || return 1
}

# -------------------------------
# Display Formatting Functions
# -------------------------------
format_value() {
    local key=$1
    local validator=$2
    local value="${CONFIG[$key]}"
    
    if $validator "$value"; then
        echo -e "${COLOR[GREEN]}${value}${COLOR[NC]}"
    else
        echo -e "${COLOR[RED]}${value:-[NOT SET]}${COLOR[NC]}"
    fi
}

format_disk() {
    if [[ -n "${CONFIG[DISK]}" ]]; then
        if validate_disk "${CONFIG[DISK]}"; then
            echo -e "${COLOR[GREEN]}${CONFIG[DISK]} (${CONFIG[DISK_SIZE]}GB)${COLOR[NC]}"
        else
            echo -e "${COLOR[RED]}${CONFIG[DISK]}${COLOR[NC]}"
        fi
    else
        echo -e "${COLOR[RED]}[NOT SET]${COLOR[NC]}"
    fi
}

format_detected() {
    local value="$1"
    local detected="$2"
    
    if [[ "$value" == "auto" && -n "$detected" ]]; then
        echo -e "${COLOR[GREEN]}${detected} (autodetect)${COLOR[NC]}"
    else
        echo -e "${COLOR[GREEN]}${value}${COLOR[NC]}"
    fi
}

# -------------------------------
# Hardware Detection
# -------------------------------
detect_hardware() {
    # CPU microcode
    local cpu_vendor=$(grep -m1 -oP 'vendor_id\s*:\s*\K.*' /proc/cpuinfo)
    case $cpu_vendor in
        *Intel*) DETECTED[MICROCODE]="intel" ;;
        *AMD*)   DETECTED[MICROCODE]="amd" ;;
    esac

    # GPU detection
    local gpu_info=$(lspci -nn | grep -i 'vga\|3d\|display')
    case $gpu_info in
        *NVIDIA*) DETECTED[GPU_DRIVER]="nvidia" ;;
        *AMD*)    DETECTED[GPU_DRIVER]="amdgpu" ;;
        *Intel*)  DETECTED[GPU_DRIVER]="i915" ;;
    esac
}

# -------------------------------
# Configuration Menu
# -------------------------------
main_menu() {
    while true; do
        clear
        echo -e "\n${COLOR[CYAN]}Arch Linux Installer${COLOR[NC]}"
        echo -e "=====================\n"
        
        # Display configuration
        printf "%2d) %-15s: %s\n" 1 "Disk" "$(format_disk)"
        printf "%2d) %-15s: %s\n" 2 "Root Size (GB)" "$(format_value ROOT_SIZE validate_size)"
        printf "%2d) %-15s: %s\n" 3 "Home Size (GB)" "$(format_value HOME_SIZE validate_size)"
        printf "%2d) %-15s: %s\n" 4 "Swap Size (GB)" "$(format_value SWAP_SIZE validate_size)"
        printf "%2d) %-15s: %s\n" 5 "Hostname" "$(format_value HOSTNAME validate_hostname)"
        printf "%2d) %-15s: %s\n" 6 "Timezone" "$(format_value TIMEZONE validate_timezone)"
        printf "%2d) %-15s: %s\n" 7 "Locale" "$(format_value LOCALE validate_locale)"
        printf "%2d) %-15s: %s\n" 8 "Keymap" "$(format_value KEYMAP validate_keymap)"
        printf "%2d) %-15s: %s\n" 9 "Username" "$(format_value USERNAME validate_username)"
        printf "%2d) %-15s: %s\n" 10 "Sudo Access" "$(format_value ADD_SUDO validate_yesno)"
        printf "%2d) %-15s: %s\n" 11 "Microcode" "$(format_detected "${CONFIG[MICROCODE]}" "${DETECTED[MICROCODE]}")"
        printf "%2d) %-15s: %s\n" 12 "GPU Driver" "$(format_detected "${CONFIG[GPU_DRIVER]}" "${DETECTED[GPU_DRIVER]}")"
        printf "%2d) %-15s: %s\n" 13 "Bootloader" "$(format_value BOOTLOADER validate_bootloader)"
        
        echo -e "\n 0) Start Installation"
        echo -e "00) Exit\n"
        
        read -p "$(echo -e ${COLOR[CYAN]}"Enter selection: "${COLOR[NC]})" choice
        
        case $choice in
            1)  select_disk ;;
            2)  set_parameter ROOT_SIZE "Enter root partition size (GB)" validate_size ;;
            3)  set_parameter HOME_SIZE "Enter home partition size (GB)" validate_size ;;
            4)  set_parameter SWAP_SIZE "Enter swap size (GB)" validate_size ;;
            5)  set_parameter HOSTNAME "Enter hostname" validate_hostname ;;
            6)  set_timezone ;;
            7)  set_locale ;;
            8)  set_keymap ;;
            9)  set_parameter USERNAME "Enter username" validate_username ;;
            10) toggle_sudo ;;
            11) set_microcode ;;
            12) set_gpu_driver ;;
            13) set_bootloader ;;
            0)  start_installation ;;
            00) exit 0 ;;
            *)  echo -e "${COLOR[RED]}Invalid selection!${COLOR[NC]}" && sleep 1 ;;
        esac
    done
}

# -------------------------------
# Parameter Setting Functions
# -------------------------------
select_disk() {
    echo -e "\nAvailable disks:"
    lsblk -d -n -l -o NAME,SIZE,TYPE | grep -v 'rom\|loop\|airoot' | while read -r line; do
        echo -e "  ${COLOR[CYAN]}${line}${COLOR[NC]}"
    done
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"\nEnter disk (e.g. /dev/sda): "${COLOR[NC]})" disk
        if validate_disk "$disk"; then
            CONFIG[DISK]="$disk"
            CONFIG[DISK_SIZE]=$(blockdev --getsize64 "$disk" | awk '{printf "%d", $1/1024/1024/1024}')
            break
        else
            echo -e "${COLOR[RED]}Invalid disk!${COLOR[NC]}"
        fi
    done
}

set_parameter() {
    local key=$1
    local prompt=$2
    local validator=$3
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"$prompt: "${COLOR[NC]})" value
        if $validator "$value"; then
            CONFIG[$key]="$value"
            if [[ "$key" =~ _SIZE ]] && ! validate_disk_space; then
                echo -e "${COLOR[RED]}Total size exceeds disk capacity!${COLOR[NC]}"
                continue
            fi
            break
        else
            echo -e "${COLOR[RED]}Invalid value!${COLOR[NC]}"
        fi
    done
}

set_timezone() {
    echo -e "\nAvailable timezones:"
    timedatectl list-timezones | head -n 20
    set_parameter TIMEZONE "Enter timezone (e.g. Europe/London)" validate_timezone
}

set_locale() {
    echo -e "\nAvailable locales:"
    grep -E '^#?[a-z].*UTF-8' /etc/locale.gen | cut -d' ' -f1 | head -n 20
    set_parameter LOCALE "Enter locale (e.g. en_US.UTF-8)" validate_locale
}

set_keymap() {
    echo -e "\nAvailable keymaps:"
    localectl list-keymaps | head -n 20
    set_parameter KEYMAP "Enter keymap (e.g. us)" validate_keymap
}

toggle_sudo() {
    CONFIG[ADD_SUDO]=$([ "${CONFIG[ADD_SUDO]}" == "yes" ] && echo "no" || echo "yes")
}

set_microcode() {
    echo -e "\n1. Auto-detect (${DETECTED[MICROCODE]})"
    echo "2. Intel"
    echo "3. AMD"
    read -p "$(echo -e ${COLOR[CYAN]}"Select microcode: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[MICROCODE]="auto" ;;
        2) CONFIG[MICROCODE]="intel" ;;
        3) CONFIG[MICROCODE]="amd" ;;
        *) echo -e "${COLOR[RED]}Invalid selection!${COLOR[NC]}" ;;
    esac
}

set_gpu_driver() {
    echo -e "\n1. Auto-detect (${DETECTED[GPU_DRIVER]})"
    echo "2. NVIDIA"
    echo "3. AMD"
    echo "4. Intel"
    read -p "$(echo -e ${COLOR[CYAN]}"Select GPU driver: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[GPU_DRIVER]="auto" ;;
        2) CONFIG[GPU_DRIVER]="nvidia" ;;
        3) CONFIG[GPU_DRIVER]="amdgpu" ;;
        4) CONFIG[GPU_DRIVER]="i915" ;;
        *) echo -e "${COLOR[RED]}Invalid selection!${COLOR[NC]}" ;;
    esac
}

set_bootloader() {
    echo -e "\n1. GRUB"
    echo "2. systemd-boot"
    read -p "$(echo -e ${COLOR[CYAN]}"Select bootloader: "${COLOR[NC]})" choice
    case $choice in
        1) CONFIG[BOOTLOADER]="grub" ;;
        2) CONFIG[BOOTLOADER]="systemd-boot" ;;
        *) echo -e "${COLOR[RED]}Invalid selection!${COLOR[NC]}" ;;
    esac
}

# -------------------------------
# Installation Functions
# -------------------------------
partition_disk() {
    local disk="${CONFIG[DISK]}"
    local part_prefix=$([[ "$disk" =~ nvme ]] && echo "p" || echo "")
    
    echo -e "\n${COLOR[YELLOW]}Partitioning disk...${COLOR[NC]}"
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart "EFI" fat32 1MiB ${UEFI_SIZE}MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart "ROOT" "$FS_TYPE" ${UEFI_SIZE}MiB "$((UEFI_SIZE + CONFIG[ROOT_SIZE] * 1024))MiB"
    
    local next_start=$((UEFI_SIZE + CONFIG[ROOT_SIZE] * 1024))
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        parted -s "$disk" mkpart "SWAP" linux-swap "${next_start}MiB" "$((next_start + CONFIG[SWAP_SIZE] * 1024))MiB"
        next_start=$((next_start + CONFIG[SWAP_SIZE] * 1024))
    fi
    
    parted -s "$disk" mkpart "HOME" "$FS_TYPE" "${next_start}MiB" 100%
}

format_partitions() {
    local disk="${CONFIG[DISK]}"
    local part_prefix=$([[ "$disk" =~ nvme ]] && echo "p" || echo "")
    
    echo -e "\n${COLOR[YELLOW]}Formatting partitions...${COLOR[NC]}"
    mkfs.fat -F32 "${disk}${part_prefix}1"
    mkfs.ext4 "${disk}${part_prefix}2"
    
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        mkswap "${disk}${part_prefix}3"
        swapon "${disk}${part_prefix}3"
    fi
    
    mkfs.ext4 "${disk}${part_prefix}$((CONFIG[SWAP_SIZE] > 0 ? 4 : 3))"
}

mount_partitions() {
    local disk="${CONFIG[DISK]}"
    local part_prefix=$([[ "$disk" =~ nvme ]] && echo "p" || echo "")
    
    echo -e "\n${COLOR[YELLOW]}Mounting partitions...${COLOR[NC]}"
    mount "${disk}${part_prefix}2" /mnt
    mkdir -p /mnt/boot
    mount "${disk}${part_prefix}1" /mnt/boot
    mkdir -p /mnt/home
    mount "${disk}${part_prefix}$((CONFIG[SWAP_SIZE] > 0 ? 4 : 3))" /mnt/home
}

install_base() {
    echo -e "\n${COLOR[YELLOW]}Installing base system...${COLOR[NC]}"
    pacstrap /mnt base base-devel linux linux-firmware
}

generate_fstab() {
    echo -e "\n${COLOR[YELLOW]}Generating fstab...${COLOR[NC]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

configure_system() {
    echo -e "\n${COLOR[YELLOW]}Configuring system...${COLOR[NC]}"
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf /usr/share/zoneinfo/${CONFIG[TIMEZONE]} /etc/localtime
    hwclock --systohc
    
    sed -i "s/^#${CONFIG[LOCALE]}/${CONFIG[LOCALE]}/" /etc/locale.gen
    locale-gen
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf
    echo "KEYMAP=${CONFIG[KEYMAP]}" > /etc/vconsole.conf
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname
    
    # Add user
    useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
    [[ "${CONFIG[ADD_SUDO]}" == "yes" ]] && sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    
    # Install bootloader
    if [[ "${CONFIG[BOOTLOADER]}" == "grub" ]]; then
        pacman -S --noconfirm grub efibootmgr
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        bootctl install
        echo "default arch" > /boot/loader/loader.conf
        echo "timeout 3" >> /boot/loader/loader.conf
        echo "title Arch Linux" > /boot/loader/entries/arch.conf
        echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
        echo "initrd /${CONFIG[MICROCODE]}.img" >> /boot/loader/entries/arch.conf
        echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
        echo "options root=PARTUUID=\$(blkid -s PARTUUID -o value ${CONFIG[DISK]}${part_prefix}2) rw" >> /boot/loader/entries/arch.conf
    fi
    
    # Install drivers
    case "${CONFIG[GPU_DRIVER]}" in
        "nvidia") pacman -S --noconfirm nvidia ;;
        "amdgpu") pacman -S --noconfirm xf86-video-amdgpu ;;
        "i915") pacman -S --noconfirm xf86-video-intel ;;
    esac
    
    # Install microcode
    [[ "${CONFIG[MICROCODE]}" != "auto" ]] && pacman -S --noconfirm ${CONFIG[MICROCODE]}-ucode
EOF
}

start_installation() {
    # Validate all parameters
    for key in DISK ROOT_SIZE HOME_SIZE SWAP_SIZE HOSTNAME TIMEZONE LOCALE KEYMAP USERNAME; do
        case $key in
            DISK) validate_disk "${CONFIG[DISK]}" || die "Invalid disk configuration" ;;
            ROOT_SIZE|HOME_SIZE|SWAP_SIZE) validate_size "${CONFIG[$key]}" || die "Invalid size for $key" ;;
            HOSTNAME) validate_hostname "${CONFIG[HOSTNAME]}" || die "Invalid hostname" ;;
            TIMEZONE) validate_timezone "${CONFIG[TIMEZONE]}" || die "Invalid timezone" ;;
            LOCALE) validate_locale "${CONFIG[LOCALE]}" || die "Invalid locale" ;;
            KEYMAP) validate_keymap "${CONFIG[KEYMAP]}" || die "Invalid keymap" ;;
            USERNAME) validate_username "${CONFIG[USERNAME]}" || die "Invalid username" ;;
        esac
    done
    
    validate_disk_space || die "Total partition sizes exceed disk capacity"
    
    # Start installation process
    partition_disk
    format_partitions
    mount_partitions
    install_base
    generate_fstab
    configure_system
    
    echo -e "\n${COLOR[GREEN]}Installation completed successfully!${COLOR[NC]}"
    umount -R /mnt
    exit 0
}

# -------------------------------
# Initialization
# -------------------------------
detect_hardware
main_menu