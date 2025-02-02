#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Check for dialog and root
# -------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if ! command -v dialog >/dev/null; then
    echo "Installing dialog..."
    pacman -Sy --noconfirm dialog
fi

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

# Detected hardware information
declare -A DETECTED=(
    [MICROCODE]=""
    [GPU_DRIVER]=""
)

# Fixed installation parameters
declare -r UEFI_SIZE=1024       # 1GB UEFI partition
declare -r FS_TYPE="ext4"       # Filesystem type

# Dialog settings
declare -r DIALOG_BACKTITLE="Arch Linux Installer"
declare -r DIALOG_HEIGHT=20
declare -r DIALOG_WIDTH=70

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

validate_bootloader() {
    [[ "$1" =~ ^(grub|systemd-boot)$ ]] && return 0 || return 1
}

validate_yesno() {
    [[ "$1" =~ ^(yes|no)$ ]] && return 0 || return 1
}

validate_disk_space() {
    [[ -z "${CONFIG[DISK_SIZE]}" ]] && return 1
    local total=$(( UEFI_SIZE + CONFIG[ROOT_SIZE] + CONFIG[HOME_SIZE] + CONFIG[SWAP_SIZE] ))
    (( total <= CONFIG[DISK_SIZE] )) && return 0 || return 1
}

# -------------------------------
# Hardware Detection Functions
# -------------------------------
detect_hardware() {
    # CPU microcode detection
    local cpu_vendor=$(grep -m1 -oP 'vendor_id\s*:\s*\K.*' /proc/cpuinfo)
    case $cpu_vendor in
        *Intel*) DETECTED[MICROCODE]="intel-ucode" ;;
        *AMD*)   DETECTED[MICROCODE]="amd-ucode" ;;
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
# Dialog Helper Functions
# -------------------------------
show_message() {
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "Message" \
           --msgbox "$1" 8 60
}

show_error() {
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "Error" \
           --colors \
           --msgbox "\Z1$1\Zn" 8 60
}

show_progress() {
    echo "$1" | dialog --backtitle "$DIALOG_BACKTITLE" \
                       --title "Progress" \
                       --gauge "$2" 8 60 0
}

# -------------------------------
# Menu Functions
# -------------------------------
main_menu() {
    while true; do
        local disk_display="${CONFIG[DISK]:-[NOT SET]}"
        [[ -n "${CONFIG[DISK_SIZE]}" ]] && disk_display+=" (${CONFIG[DISK_SIZE]}GB)"
        
        local microcode_display="${CONFIG[MICROCODE]}"
        [[ "$microcode_display" == "auto" ]] && microcode_display+=" (${DETECTED[MICROCODE]})"
        
        local gpu_display="${CONFIG[GPU_DRIVER]}"
        [[ "$gpu_display" == "auto" ]] && gpu_display+=" (${DETECTED[GPU_DRIVER]})"

        local choice
        choice=$(dialog --clear --backtitle "$DIALOG_BACKTITLE" \
                       --title "Main Menu" \
                       --colors \
                       --menu "Select option to configure:" \
                       $DIALOG_HEIGHT $DIALOG_WIDTH 13 \
                       "1" "Disk: $disk_display" \
                       "2" "Root Size: ${CONFIG[ROOT_SIZE]}GB" \
                       "3" "Home Size: ${CONFIG[HOME_SIZE]}GB" \
                       "4" "Swap Size: ${CONFIG[SWAP_SIZE]}GB" \
                       "5" "Hostname: ${CONFIG[HOSTNAME]}" \
                       "6" "Timezone: ${CONFIG[TIMEZONE]}" \
                       "7" "Locale: ${CONFIG[LOCALE]}" \
                       "8" "Keymap: ${CONFIG[KEYMAP]}" \
                       "9" "Username: ${CONFIG[USERNAME]:-[NOT SET]}" \
                       "10" "Sudo Access: ${CONFIG[ADD_SUDO]}" \
                       "11" "Microcode: $microcode_display" \
                       "12" "GPU Driver: $gpu_display" \
                       "13" "Bootloader: ${CONFIG[BOOTLOADER]}" \
                       "i" "Start Installation" \
                       "q" "Exit" \
                       2>&1 >/dev/tty)

        case $choice in
            1) select_disk ;;
            2) set_size "ROOT_SIZE" "Enter root partition size (GB)" ;;
            3) set_size "HOME_SIZE" "Enter home partition size (GB)" ;;
            4) set_size "SWAP_SIZE" "Enter swap size (GB)" ;;
            5) set_hostname ;;
            6) select_timezone ;;
            7) select_locale ;;
            8) select_keymap ;;
            9) set_username ;;
            10) toggle_sudo ;;
            11) select_microcode ;;
            12) select_gpu_driver ;;
            13) select_bootloader ;;
            i) start_installation ;;
            q) exit 0 ;;
            *) continue ;;
        esac
    done
}

# -------------------------------
# Parameter Setting Functions
# -------------------------------
select_disk() {
    local disks=($(lsblk -d -n -l -o NAME,SIZE,TYPE | grep -v 'rom\|loop\|airoot'))
    local menu_items=()
    
    for disk in "${disks[@]}"; do
        menu_items+=("/dev/$(echo $disk | awk '{print $1}')" "$(echo $disk | awk '{print $2}')")
    done

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select Disk" \
                   --menu "Available disks:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
                   "${menu_items[@]}" \
                   2>&1 >/dev/tty)

    if [[ -n "$choice" ]]; then
        CONFIG[DISK]="$choice"
        CONFIG[DISK_SIZE]=$(blockdev --getsize64 "$choice" | awk '{printf "%d", $1/1024/1024/1024}')
    fi
}

set_size() {
    local key=$1
    local prompt=$2
    
    while true; do
        local value
        value=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                      --title "Set $key" \
                      --inputbox "$prompt" \
                      8 40 "${CONFIG[$key]}" \
                      2>&1 >/dev/tty)
        
        [[ $? -ne 0 ]] && return

        if validate_size "$value"; then
            CONFIG[$key]="$value"
            if ! validate_disk_space; then
                show_error "Total size exceeds disk capacity!"
                continue
            fi
            break
        else
            show_error "Please enter a valid number"
        fi
    done
}

set_hostname() {
    while true; do
        local value
        value=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                      --title "Set Hostname" \
                      --inputbox "Enter hostname:" \
                      8 40 "${CONFIG[HOSTNAME]}" \
                      2>&1 >/dev/tty)
        
        [[ $? -ne 0 ]] && return

        if validate_hostname "$value"; then
            CONFIG[HOSTNAME]="$value"
            break
        else
            show_error "Invalid hostname format"
        fi
    done
}

# -------------------------------
# Special Parameter Selection Functions
# -------------------------------
select_timezone() {
    # Create a list of timezones
    local zones=()
    while IFS= read -r zone; do
        zones+=("$zone" "")
    done < <(find /usr/share/zoneinfo/ -type f -not -path '*right*' -not -path '*posix*' \
             | cut -d/ -f5- | sort | grep -v "^posix/" | grep -v "^right/")

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select Timezone" \
                   --menu "Select your timezone:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 13 \
                   "${zones[@]}" \
                   2>&1 >/dev/tty)

    [[ $? -eq 0 ]] && CONFIG[TIMEZONE]="$choice"
}

select_locale() {
    # Create a list of locales
    local locales=()
    while IFS= read -r line; do
        [[ "$line" =~ ^#?([a-z][a-z]_[A-Z][A-Z].*)$ ]] && \
            locales+=("${BASH_REMATCH[1]}" "")
    done < /etc/locale.gen

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select Locale" \
                   --menu "Select your locale:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 13 \
                   "${locales[@]}" \
                   2>&1 >/dev/tty)

    [[ $? -eq 0 ]] && CONFIG[LOCALE]="$choice"
}

select_keymap() {
    # Create a list of keymaps
    local keymaps=()
    while IFS= read -r keymap; do
        keymaps+=("$keymap" "")
    done < <(localectl list-keymaps)

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select Keymap" \
                   --menu "Select your keyboard layout:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 13 \
                   "${keymaps[@]}" \
                   2>&1 >/dev/tty)

    [[ $? -eq 0 ]] && CONFIG[KEYMAP]="$choice"
}

set_username() {
    while true; do
        local value
        value=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                      --title "Set Username" \
                      --inputbox "Enter username:" \
                      8 40 "${CONFIG[USERNAME]}" \
                      2>&1 >/dev/tty)
        
        [[ $? -ne 0 ]] && return

        if validate_username "$value"; then
            CONFIG[USERNAME]="$value"
            break
        else
            show_error "Invalid username format"
        fi
    done
}

toggle_sudo() {
    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Sudo Access" \
                   --yes-label "Yes" \
                   --no-label "No" \
                   --yesno "Enable sudo access for user?" \
                   8 40 \
                   2>&1 >/dev/tty)
    
    [[ $? -eq 0 ]] && CONFIG[ADD_SUDO]="yes" || CONFIG[ADD_SUDO]="no"
}

select_microcode() {
    local options=("auto" "Autodetect (${DETECTED[MICROCODE]})"
                  "intel-ucode" "Intel CPU"
                  "amd-ucode" "AMD CPU")

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select Microcode" \
                   --menu "Select CPU microcode:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 4 \
                   "${options[@]}" \
                   2>&1 >/dev/tty)

    [[ $? -eq 0 ]] && CONFIG[MICROCODE]="$choice"
}

select_gpu_driver() {
    local options=("auto" "Autodetect (${DETECTED[GPU_DRIVER]})"
                  "nvidia" "NVIDIA GPU"
                  "amdgpu" "AMD GPU"
                  "i915" "Intel GPU")

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select GPU Driver" \
                   --menu "Select GPU driver:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 5 \
                   "${options[@]}" \
                   2>&1 >/dev/tty)

    [[ $? -eq 0 ]] && CONFIG[GPU_DRIVER]="$choice"
}

select_bootloader() {
    local options=("grub" "GRUB bootloader"
                  "systemd-boot" "systemd-boot")

    local choice
    choice=$(dialog --backtitle "$DIALOG_BACKTITLE" \
                   --title "Select Bootloader" \
                   --menu "Select bootloader:" \
                   $DIALOG_HEIGHT $DIALOG_WIDTH 3 \
                   "${options[@]}" \
                   2>&1 >/dev/tty)

    [[ $? -eq 0 ]] && CONFIG[BOOTLOADER]="$choice"
}

# -------------------------------
# Installation Functions
# -------------------------------
start_installation() {
    # Validate all parameters before starting
    local errors=()
    [[ -z "${CONFIG[DISK]}" ]] && errors+=("Disk not selected")
    [[ -z "${CONFIG[USERNAME]}" ]] && errors+=("Username not set")
    ! validate_disk_space && errors+=("Total partition size exceeds disk capacity")

    if (( ${#errors[@]} > 0 )); then
        local error_msg="Cannot start installation:\n\n"
        for error in "${errors[@]}"; do
            error_msg+="• $error\n"
        done
        show_error "$error_msg"
        return 1
    fi

    # Show confirmation dialog
    local confirm_msg="Please confirm the installation settings:\n\n"
    confirm_msg+="Disk: ${CONFIG[DISK]} (${CONFIG[DISK_SIZE]}GB)\n"
    confirm_msg+="Root Size: ${CONFIG[ROOT_SIZE]}GB\n"
    confirm_msg+="Home Size: ${CONFIG[HOME_SIZE]}GB\n"
    confirm_msg+="Swap Size: ${CONFIG[SWAP_SIZE]}GB\n"
    confirm_msg+="Hostname: ${CONFIG[HOSTNAME]}\n"
    confirm_msg+="Username: ${CONFIG[USERNAME]}\n"
    confirm_msg+="\nWARNING: This will erase all data on ${CONFIG[DISK]}"

    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "Confirm Installation" \
           --yesno "$confirm_msg" \
           20 60 || return

    # Start installation with progress bar
    (
        partition_disk 10
        format_partitions 30
        mount_partitions 40
        install_base 60
        configure_system 80
        install_bootloader 90
        finalize_installation 100
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
               --title "Installing" \
               --gauge "Preparing installation..." \
               8 60 0
}

partition_disk() {
    local percent=$1
    echo -e "XXX\n$percent\nPartitioning disk...\nXXX"
    
    local disk="${CONFIG[DISK]}"
    local part_prefix
    [[ "$disk" =~ "nvme" ]] && part_prefix="p" || part_prefix=""

    # Create partition table
    parted -s "$disk" mklabel gpt

    # Calculate partition sizes in MB
    local start=1
    local end=$((start + UEFI_SIZE))
    
    # EFI partition
    parted -s "$disk" mkpart "EFI" fat32 ${start}MiB ${end}MiB
    parted -s "$disk" set 1 esp on
    
    # Root partition
    start=$end
    end=$((start + CONFIG[ROOT_SIZE] * 1024))
    parted -s "$disk" mkpart "ROOT" ${start}MiB ${end}MiB
    
    # Swap partition (if enabled)
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        start=$end
        end=$((start + CONFIG[SWAP_SIZE] * 1024))
        parted -s "$disk" mkpart "SWAP" linux-swap ${start}MiB ${end}MiB
    fi
    
    # Home partition
    start=$end
    end=$((start + CONFIG[HOME_SIZE] * 1024))
    parted -s "$disk" mkpart "HOME" ${start}MiB ${end}MiB
}

format_partitions() {
    local percent=$1
    echo -e "XXX\n$percent\nFormatting partitions...\nXXX"
    
    local disk="${CONFIG[DISK]}"
    local part_prefix
    [[ "$disk" =~ "nvme" ]] && part_prefix="p" || part_prefix=""
    
    # Format EFI partition
    mkfs.fat -F32 "${disk}${part_prefix}1"
    
    # Format root partition
    mkfs.ext4 -F "${disk}${part_prefix}2"
    
    # Format swap (if enabled)
    if (( CONFIG[SWAP_SIZE] > 0 )); then
        mkswap "${disk}${part_prefix}3"
        swapon "${disk}${part_prefix}3"
    fi
    
    # Format home partition
    mkfs.ext4 -F "${disk}${part_prefix}4"
}

mount_partitions() {
    local percent=$1
    echo -e "XXX\n$percent\nMounting partitions...\nXXX"
    
    local disk="${CONFIG[DISK]}"
    local part_prefix
    [[ "$disk" =~ "nvme" ]] && part_prefix="p" || part_prefix=""
    
    # Mount root
    mount "${disk}${part_prefix}2" /mnt
    
    # Create and mount other directories
    mkdir -p /mnt/{boot,home}
    mount "${disk}${part_prefix}1" /mnt/boot
    mount "${disk}${part_prefix}4" /mnt/home
}

install_base() {
    local percent=$1
    echo -e "XXX\n$percent\nInstalling base system...\nXXX"
    
    # Install base packages
    pacstrap /mnt base base-devel linux linux-firmware \
        networkmanager sudo vim
}

configure_system() {
    local percent=$1
    echo -e "XXX\n$percent\nConfiguring system...\nXXX"
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Configure system
    arch-chroot /mnt /bin/bash <<EOF
    # Set timezone
    ln -sf /usr/share/zoneinfo/${CONFIG[TIMEZONE]} /etc/localtime
    hwclock --systohc
    
    # Set locale
    sed -i "s/^#${CONFIG[LOCALE]}/${CONFIG[LOCALE]}/" /etc/locale.gen
    locale-gen
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf
    
    # Set keymap
    echo "KEYMAP=${CONFIG[KEYMAP]}" > /etc/vconsole.conf
    
    # Set hostname
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname
    
    # Create user
    useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
    echo "${CONFIG[USERNAME]} ALL=(ALL) ALL" >> /etc/sudoers.d/10-${CONFIG[USERNAME]}
    
    # Enable services
    systemctl enable NetworkManager
EOF
}

install_bootloader() {
    local percent=$1
    echo -e "XXX\n$percent\nInstalling bootloader...\nXXX"
    
    if [[ "${CONFIG[BOOTLOADER]}" == "grub" ]]; then
        arch-chroot /mnt /bin/bash <<EOF
        pacman -S --noconfirm grub efibootmgr
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        grub-mkconfig -o /boot/grub/grub.cfg
EOF
    else
        arch-chroot /mnt /bin/bash <<EOF
        bootctl install
        echo "default arch" > /boot/loader/loader.conf
        echo "timeout 3" >> /boot/loader/loader.conf
        echo "editor 0" >> /boot/loader/loader.conf
EOF
    fi
}

finalize_installation() {
    local percent=$1
    echo -e "XXX\n$percent\nFinalizing installation...\nXXX"
    sync
    sleep 2
}

# -------------------------------
# Start Installation
# -------------------------------
detect_hardware
main_menu