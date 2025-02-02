#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Check for whiptail and root
# -------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if ! command -v whiptail >/dev/null; then
    echo "Installing whiptail..."
    pacman -Sy --noconfirm libnewt
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

# Whiptail settings
declare -r BACKTITLE="Arch Linux Installer"
declare -r TERM_HEIGHT=24
declare -r TERM_WIDTH=78
declare -r MENU_HEIGHT=16

# -------------------------------
# Helper Functions
# -------------------------------
show_message() {
    whiptail --backtitle "$BACKTITLE" \
             --title "Message" \
             --msgbox "$1" 8 60
}

show_error() {
    whiptail --backtitle "$BACKTITLE" \
             --title "Error" \
             --msgbox "$1" 8 60
}

show_yesno() {
    whiptail --backtitle "$BACKTITLE" \
             --title "$1" \
             --yesno "$2" 8 60
}

show_progress() {
    {
        for i in $(seq 1 100); do
            echo $i
            sleep 0.02
        done
    } | whiptail --backtitle "$BACKTITLE" \
                 --title "Progress" \
                 --gauge "$1" 8 60 0
}

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
        choice=$(whiptail --backtitle "$BACKTITLE" \
                         --title "Main Menu" \
                         --menu "Select option to configure:" \
                         $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
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
                         3>&1 1>&2 2>&3)

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
        local name="/dev/$(echo $disk | awk '{print $1}')"
        local size="$(echo $disk | awk '{print $2}')"
        menu_items+=("$name" "$size")
    done

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select Disk" \
                     --menu "Available disks:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${menu_items[@]}" \
                     3>&1 1>&2 2>&3)

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
        value=$(whiptail --backtitle "$BACKTITLE" \
                        --title "Set $key" \
                        --inputbox "$prompt" \
                        8 60 "${CONFIG[$key]}" \
                        3>&1 1>&2 2>&3)
        
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
        value=$(whiptail --backtitle "$BACKTITLE" \
                        --title "Set Hostname" \
                        --inputbox "Enter hostname:" \
                        8 60 "${CONFIG[HOSTNAME]}" \
                        3>&1 1>&2 2>&3)
        
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
    # First, select region
    local regions=()
    while IFS= read -r region; do
        [[ -d "/usr/share/zoneinfo/$region" ]] && regions+=("$region" "")
    done < <(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)

    local region
    region=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select Region" \
                     --menu "Select your region:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${regions[@]}" \
                     3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return

    # Then select city
    local cities=()
    while IFS= read -r city; do
        cities+=("$city" "")
    done < <(find "/usr/share/zoneinfo/$region" -type f -printf "%f\n" | sort)

    local city
    city=$(whiptail --backtitle "$BACKTITLE" \
                   --title "Select City" \
                   --menu "Select your city:" \
                   $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                   "${cities[@]}" \
                   3>&1 1>&2 2>&3)
    
    [[ $? -eq 0 ]] && CONFIG[TIMEZONE]="$region/$city"
}

select_locale() {
    local locales=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^#?([a-z][a-z]_[A-Z][A-Z].*)$ ]]; then
            local locale="${BASH_REMATCH[1]}"
            locales+=("$locale" "")
        fi
    done < /etc/locale.gen

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select Locale" \
                     --menu "Select your locale:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${locales[@]}" \
                     3>&1 1>&2 2>&3)
    
    [[ $? -eq 0 ]] && CONFIG[LOCALE]="$choice"
}

select_keymap() {
    local keymaps=()
    while IFS= read -r keymap; do
        keymaps+=("$keymap" "")
    done < <(localectl list-keymaps)

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select Keymap" \
                     --menu "Select your keyboard layout:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${keymaps[@]}" \
                     3>&1 1>&2 2>&3)
    
    [[ $? -eq 0 ]] && CONFIG[KEYMAP]="$choice"
}

set_username() {
    while true; do
        local value
        value=$(whiptail --backtitle "$BACKTITLE" \
                        --title "Set Username" \
                        --inputbox "Enter username:" \
                        8 60 "${CONFIG[USERNAME]}" \
                        3>&1 1>&2 2>&3)
        
        [[ $? -ne 0 ]] && return

        if validate_username "$value"; then
            CONFIG[USERNAME]="$value"
            # Ask for password
            local password
            password=$(whiptail --backtitle "$BACKTITLE" \
                              --title "Set Password" \
                              --passwordbox "Enter password for $value:" \
                              8 60 \
                              3>&1 1>&2 2>&3)
            
            [[ $? -ne 0 ]] && return
            
            local password2
            password2=$(whiptail --backtitle "$BACKTITLE" \
                               --title "Confirm Password" \
                               --passwordbox "Confirm password:" \
                               8 60 \
                               3>&1 1>&2 2>&3)
            
            [[ $? -ne 0 ]] && return
            
            if [[ "$password" == "$password2" ]]; then
                CONFIG[USER_PASSWORD]="$password"
                break
            else
                show_error "Passwords do not match!"
            fi
        else
            show_error "Invalid username format"
        fi
    done
}

toggle_sudo() {
    if whiptail --backtitle "$BACKTITLE" \
                --title "Sudo Access" \
                --yesno "Enable sudo access for user?" \
                8 60; then
        CONFIG[ADD_SUDO]="yes"
    else
        CONFIG[ADD_SUDO]="no"
    fi
}

select_microcode() {
    local options=(
        "auto" "Autodetect (${DETECTED[MICROCODE]})"
        "intel-ucode" "Intel CPU"
        "amd-ucode" "AMD CPU"
        "none" "No microcode updates"
    )

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select Microcode" \
                     --menu "Select CPU microcode:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${options[@]}" \
                     3>&1 1>&2 2>&3)
    
    [[ $? -eq 0 ]] && CONFIG[MICROCODE]="$choice"
}

select_gpu_driver() {
    local options=(
        "auto" "Autodetect (${DETECTED[GPU_DRIVER]})"
        "nvidia" "NVIDIA GPU"
        "amdgpu" "AMD GPU"
        "i915" "Intel GPU"
        "none" "No GPU driver"
    )

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select GPU Driver" \
                     --menu "Select GPU driver:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${options[@]}" \
                     3>&1 1>&2 2>&3)
    
    [[ $? -eq 0 ]] && CONFIG[GPU_DRIVER]="$choice"
}

select_bootloader() {
    local options=(
        "grub" "GRUB bootloader"
        "systemd-boot" "systemd-boot"
    )

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
                     --title "Select Bootloader" \
                     --menu "Select bootloader:" \
                     $TERM_HEIGHT $TERM_WIDTH $MENU_HEIGHT \
                     "${options[@]}" \
                     3>&1 1>&2 2>&3)
    
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
        whiptail --backtitle "$BACKTITLE" \
                 --title "Error" \
                 --msgbox "$error_msg" 12 60
        return 1
    fi

    # Show confirmation dialog
    local confirm_msg="Please review your installation settings:\n\n"
    confirm_msg+="Disk: ${CONFIG[DISK]} (${CONFIG[DISK_SIZE]}GB)\n"
    confirm_msg+="Root Size: ${CONFIG[ROOT_SIZE]}GB\n"
    confirm_msg+="Home Size: ${CONFIG[HOME_SIZE]}GB\n"
    confirm_msg+="Swap Size: ${CONFIG[SWAP_SIZE]}GB\n"
    confirm_msg+="Hostname: ${CONFIG[HOSTNAME]}\n"
    confirm_msg+="Username: ${CONFIG[USERNAME]}\n"
    confirm_msg+="Timezone: ${CONFIG[TIMEZONE]}\n"
    confirm_msg+="Locale: ${CONFIG[LOCALE]}\n"
    confirm_msg+="Keymap: ${CONFIG[KEYMAP]}\n"
    confirm_msg+="Sudo Access: ${CONFIG[ADD_SUDO]}\n"
    confirm_msg+="Microcode: ${CONFIG[MICROCODE]}\n"
    confirm_msg+="GPU Driver: ${CONFIG[GPU_DRIVER]}\n"
    confirm_msg+="Bootloader: ${CONFIG[BOOTLOADER]}\n\n"
    confirm_msg+="WARNING: This will erase all data on ${CONFIG[DISK]}"

    if ! whiptail --backtitle "$BACKTITLE" \
                  --title "Confirm Installation" \
                  --yesno "$confirm_msg" 24 70; then
        return 1
    fi

    # Installation steps with progress bar
    (
        show_progress "Partitioning disk..." 10
        partition_disk
        
        show_progress "Formatting partitions..." 20
        format_partitions
        
        show_progress "Mounting partitions..." 30
        mount_partitions
        
        show_progress "Installing base system..." 40
        install_base
        
        show_progress "Configuring system..." 60
        configure_system
        
        show_progress "Installing bootloader..." 80
        install_bootloader
        
        show_progress "Finalizing installation..." 90
        finalize_installation
        
        show_progress "Installation complete!" 100
        sleep 2
    ) | whiptail --backtitle "$BACKTITLE" \
                 --title "Installing" \
                 --gauge "Preparing installation..." \
                 8 70 0
}

partition_disk() {
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
    # Install base packages
    pacstrap /mnt base base-devel linux linux-firmware \
        networkmanager sudo vim
        
    # Install microcode if selected
    if [[ "${CONFIG[MICROCODE]}" != "none" ]]; then
        local microcode="${CONFIG[MICROCODE]}"
        [[ "$microcode" == "auto" ]] && microcode="${DETECTED[MICROCODE]}"
        pacstrap /mnt "$microcode"
    fi
    
    # Install GPU driver if selected
    if [[ "${CONFIG[GPU_DRIVER]}" != "none" ]]; then
        local driver="${CONFIG[GPU_DRIVER]}"
        [[ "$driver" == "auto" ]] && driver="${DETECTED[GPU_DRIVER]}"
        pacstrap /mnt "$driver"
    fi
}

configure_system() {
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
    
    # Create user and set password
    useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
    echo "${CONFIG[USERNAME]}:${CONFIG[USER_PASSWORD]}" | chpasswd
    
    # Configure sudo access
    if [[ "${CONFIG[ADD_SUDO]}" == "yes" ]]; then
        echo "${CONFIG[USERNAME]} ALL=(ALL) ALL" > /etc/sudoers.d/10-${CONFIG[USERNAME]}
        chmod 440 /etc/sudoers.d/10-${CONFIG[USERNAME]}
    fi
    
    # Enable services
    systemctl enable NetworkManager
EOF
}

install_bootloader() {
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
    sync
    sleep 2
}

# -------------------------------
# Start Installation
# -------------------------------
detect_hardware
main_menu