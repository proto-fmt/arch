#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Global configuration with validation states
declare -A CONFIG=(
    [DISK]=""                   # /dev/sdX or /dev/nvmeXn1
    [ROOT_SIZE]="20"            # Positive integer in GB
    [HOME_SIZE]="10"            # Positive integer in GB
    [SWAP_SIZE]="0"             # Non-negative integer in GB
    [HOSTNAME]="archlinux"      # Valid hostname
    [TIMEZONE]="UTC"            # Existing timezone
    [LOCALE]="en_US.UTF-8"      # Available locale
    [KEYMAP]="us"               # Valid keymap
    [USERNAME]=""               # Valid UNIX username
    [ADD_SUDO]="yes"            # yes/no
    [MICROCODE]="auto"          # auto/intel/amd
    [GPU_DRIVER]="auto"         # auto/nvidia/amdgpu/i915
    [BOOTLOADER]="grub"         # grub/systemd-boot
)

# Fixed parameters
declare -r UEFI_SIZE=1024       # Fixed 1GB UEFI partition
declare -r FS_TYPE="ext4"        # Only ext4 filesystem

# Color configuration
declare -r -A COLOR=(
    [RED]=$(tput setaf 1)
    [GREEN]=$(tput setaf 2)
    [YELLOW]=$(tput setaf 3)
    [CYAN]=$(tput setaf 6)
    [NC]=$(tput sgr0)
)

# Validation functions
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

# Color formatting based on validation
format_value() {
    local key="$1"
    local value="${CONFIG[$key]}"
    
    case $key in
        DISK)
            validate_disk "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        ROOT_SIZE|HOME_SIZE|SWAP_SIZE)
            validate_size "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        HOSTNAME)
            validate_hostname "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        TIMEZONE)
            validate_timezone "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        LOCALE)
            validate_locale "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        KEYMAP)
            validate_keymap "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        USERNAME)
            validate_username "$value" && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
        *)  # For yes/no and other simple fields
            [[ -n "$value" ]] && color=${COLOR[GREEN]} || color=${COLOR[RED]}
            ;;
    esac
    
    echo -e "${color}${value:-[NOT SET]}${COLOR[NC]}"
}

# Main configuration menu
main_menu() {
    while true; do
        clear
        echo -e "\n${COLOR[CYAN]}Arch Linux Installer Configuration${COLOR[NC]}"
        echo -e "------------------------------------\n"
        
        # Display all configuration parameters
        local i=1
        printf "%2d) %-15s: %s\n" $i "Disk" "$(format_value DISK)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Root Size (GB)" "$(format_value ROOT_SIZE)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Home Size (GB)" "$(format_value HOME_SIZE)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Swap Size (GB)" "$(format_value SWAP_SIZE)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Hostname" "$(format_value HOSTNAME)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Timezone" "$(format_value TIMEZONE)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Locale" "$(format_value LOCALE)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Keymap" "$(format_value KEYMAP)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Username" "$(format_value USERNAME)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Sudo Access" "$(format_value ADD_SUDO)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Microcode" "$(format_value MICROCODE)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "GPU Driver" "$(format_value GPU_DRIVER)"; ((i++))
        printf "%2d) %-15s: %s\n" $i "Bootloader" "$(format_value BOOTLOADER)"; ((i++))
        
        echo -e "\n 0) Start Installation"
        echo -e "00) Exit\n"
        
        read -p "$(echo -e ${COLOR[CYAN]}"Enter selection: "${COLOR[NC]})" choice
        
        case $choice in
            1) set_parameter DISK "Enter disk path (e.g. /dev/sda)" validate_disk ;;
            2) set_parameter ROOT_SIZE "Enter root partition size (GB)" validate_size ;;
            3) set_parameter HOME_SIZE "Enter home partition size (GB)" validate_size ;;
            4) set_parameter SWAP_SIZE "Enter swap size (GB)" validate_size ;;
            5) set_parameter HOSTNAME "Enter hostname" validate_hostname ;;
            6) set_timezone ;;
            7) set_locale ;;
            8) set_keymap ;;
            9) set_parameter USERNAME "Enter username" validate_username ;;
            10) toggle_sudo ;;
            11) set_microcode ;;
            12) set_gpu_driver ;;
            13) set_bootloader ;;
            0) install_system ;;
            00) exit 0 ;;
            *) echo -e "${COLOR[RED]}Invalid selection!${COLOR[NC]}" && sleep 1 ;;
        esac
    done
}

# Generic parameter setter with validation
set_parameter() {
    local key=$1
    local prompt=$2
    local validator=$3
    
    while true; do
        read -p "$(echo -e ${COLOR[CYAN]}"$prompt: "${COLOR[NC]})" value
        if $validator "$value"; then
            CONFIG[$key]="$value"
            return 0
        else
            echo -e "${COLOR[RED]}Invalid value!${COLOR[NC]}"
        fi
    done
}

# Specialized setters for complex parameters
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

# Installation functions (simplified example)
install_system() {
    echo -e "\n${COLOR[YELLOW]}Validating configuration...${COLOR[NC]}"
    for key in "${!CONFIG[@]}"; do
        case $key in
            DISK|TIMEZONE|LOCALE|KEYMAP|USERNAME)
                if ! format_value "$key" | grep -q "${COLOR[GREEN]}"; then
                    echo -e "${COLOR[RED]}Invalid $key configuration!${COLOR[NC]}"
                    return 1
                fi
                ;;
        esac
    done
    
    echo -e "\n${COLOR[GREEN]}Starting installation...${COLOR[NC]}"
    # Add actual installation logic here
    exit 0
}

# Start the installer
main_menu