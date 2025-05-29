#!/usr/bin/env bash

# --- Original script information ---
# Original Author: tteck (tteckster)
# Original Copyright: Copyright (c) 2021-2025 tteck
# Original License: MIT
# Original Source: https://github.com/community-scripts/ProxmoxVE/blob/main/vm/mikrotik-routeros.sh
#
# --- Modifications by os4-dev ---
# Copyright 2023-2025 os4-dev
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This script is a modification of the original script by tteck.
# The core logic for Mikrotik CHR deployment remains, adapted to fit
# the infra-commons project structure and coding style.
# Refer to the NOTICE file in the root of the infra-commons repository for full licensing details.

# UA: --- Початкове налаштування скрипту ---
# EN: --- Stop script on first error, treat unset variables as an error, and handle pipeline failures ---
set -e # UA: Зупиняти при першій помилці
set -u # UA: Вважати помилкою використання неініціалізованих змінних
set -o pipefail # UA: Вважати помилкою, якщо будь-яка команда в конвеєрі завершується з помилкою

# UA: --- Кольори та атрибути для виводу (використовуємо tput для кращої сумісності) ---
# EN: --- Colors and attributes for output (using tput for better compatibility) ---
C_RESET=$(tput sgr0 2>/dev/null || echo '\033[0m')
C_RED=$(tput setaf 1 2>/dev/null || echo '\033[0;31m')
C_GREEN=$(tput setaf 2 2>/dev/null || echo '\033[0;32m')
C_YELLOW=$(tput setaf 3 2>/dev/null || echo '\033[0;33m')
C_BLUE=$(tput setaf 4 2>/dev/null || echo '\033[0;34m')
C_BOLD=$(tput bold 2>/dev/null || echo '\033[1m')

# UA: --- Функції для логування ---
# EN: --- Logging functions ---
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; } # UA: Помилки виводимо в stderr

# UA: --- Значення за замовчуванням ---
# EN: --- Default values ---
DEFAULT_VMID_PREFIX="91" 
DEFAULT_HN_PREFIX="mikrotik-chr"
DEFAULT_CORES="1" 
DEFAULT_RAM_MB="256" 
DEFAULT_DISK_SIZE="1G" 
DEFAULT_BRIDGE="vmbr0"
DEFAULT_VLAN=""
DEFAULT_MTU=""
DEFAULT_START_VM="no" 
DEFAULT_CHR_VERSION="7.15.3" 
DEFAULT_IMAGE_BASE_URL="https://download.mikrotik.com/routeros" 
DEFAULT_TAGS="mikrotik,routeros,chr,automated-template" 
DEFAULT_DOWNLOAD_DIR="/var/lib/vz/template/iso" 
DEFAULT_SCRIPT_LANG="en" 
DEFAULT_IMAGE_STORAGE="" 
DEFAULT_FORCE_DOWNLOAD="no"

# UA: --- Робочі змінні (будуть ініціалізовані пізніше) ---
# EN: --- Working variables (will be initialized later) ---
VMID=""
HN=""
CORE_COUNT=""
RAM_SIZE=""
DISK_SIZE="" 
BRIDGE=""
MAC_ADDRESS=""
VLAN_TAG=""
MTU_SIZE=""
START_VM=""
PROXMOX_STORAGE=""
CHR_VERSION=""      
IMAGE_BASE_URL=""   
IMAGE_URL=""        # UA: Тепер завжди формується з CHR_VERSION та IMAGE_BASE_URL
ADDITIONAL_TAGS=""
FINAL_TAGS=""
TEMP_DIR="" 
LOCAL_IMAGE_ZIP_PATH="" 
FINAL_IMAGE_PATH_ON_STORAGE="" 
INTERACTIVE_MODE="false" 
SCRIPT_LANG="" 
IMAGE_STORAGE=""      
IMAGE_STORAGE_PATH="" 
IMAGE_STORAGE_TYPE="" 
FORCE_DOWNLOAD=""

# UA: --- Зберігаємо BASH_COMMAND та LINENO для відстеження помилок ---
# EN: --- Store the BASH_COMMAND and LINENO for error trapping ---
LAST_COMMAND=""
LAST_LINE=0

# UA: --- Обробка помилок ---
# EN: --- Error handling ---
error_exit() {
    trap - ERR SIGINT SIGTERM EXIT 
    local exit_code=$?
    log_error "Script failed on line $LAST_LINE with exit code $exit_code."
    log_error "Failing command: $LAST_COMMAND"
    [[ -n "${VMID:-}" && -n "${PROXMOX_STORAGE:-}" ]] && cleanup_vmid_on_error || true 
    cleanup_temp_dir 
    log_info "For details, see the script execution log."
    exit "$exit_code"
}

# UA: --- Очищення ВМ при помилці, якщо частково створена ---
# EN: --- Cleanup VM on error if partially created ---
cleanup_vmid_on_error() {
    if qm status "$VMID" >/dev/null 2>&1; then 
        log_info "Attempting to clean up partially created VM ${VMID}..."
        if [[ "$(qm status "$VMID" | awk '{print $2}')" == "running" ]]; then 
            qm stop "$VMID" --timeout 30 || log_warn "Could not stop VM ${VMID}."
        fi
        qm destroy "$VMID" --purge --destroy-unreferenced-disks 1 || log_warn "Could not automatically destroy VM ${VMID}."
    fi
}

# UA: --- Очищення тимчасової директорії ---
# EN: --- Cleanup temporary directory ---
cleanup_temp_dir() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then 
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# UA: --- Перехоплення помилок та виходу зі скрипту ---
# EN: --- Trap errors and script exit ---
trap 'LAST_COMMAND="$BASH_COMMAND"; LAST_LINE="$LINENO"; error_exit' ERR
trap 'log_info "Script interrupted."; cleanup_temp_dir; exit 130' SIGINT
trap 'log_info "Script terminated."; cleanup_temp_dir; exit 143' SIGTERM
trap 'cleanup_temp_dir' EXIT 


# EN: --- Function to display help message ---
show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "This script automates the creation of a Mikrotik RouterOS CHR VM on Proxmox VE."
    echo "Based on the script by tteck from community-scripts/ProxmoxVE."
    echo "Part of Proxmox OS4DEV Scripts collection." 
    echo ""
    echo "Options:"
    echo "  -h, --help                  Show this help message and exit."
    echo "  -i, --interactive           Force interactive mode using whiptail (prompts for all settings)."
    echo "  --lang LANG_CODE            Set script language for interactive prompts ('en' or 'uk', default: ${DEFAULT_SCRIPT_LANG})." 
    echo "  --chr-version VERSION       CHR version to download (e.g., 7.15.3, default: ${DEFAULT_CHR_VERSION}). This forms the download URL."
    echo "  --image-base-url URL_BASE   Base URL for Mikrotik CHR images (default: ${DEFAULT_IMAGE_BASE_URL}). Used with --chr-version."
    echo "  --vmid ID                   Set Virtual Machine ID (default: auto-generated starting with ${DEFAULT_VMID_PREFIX}XX)."
    echo "  --hn, --hostname NAME       Set VM hostname (default: ${DEFAULT_HN_PREFIX}-<vmid>)."
    echo "  --cores COUNT               Allocate CPU cores (default: ${DEFAULT_CORES})."
    echo "  --ram MB                    Allocate RAM in MB (default: ${DEFAULT_RAM_MB})."
    echo "  --bridge BRIDGE             Set network bridge (default: ${DEFAULT_BRIDGE})."
    echo "  --mac HWADDR                Set MAC address (default: auto-generated)."
    echo "  --vlan TAG                  Set VLAN tag (default: none)."
    echo "  --mtu SIZE                  Set interface MTU size (default: system default)."
    echo "  --storage STORAGE_ID        Proxmox storage ID for the VM disk (REQUIRED for non-interactive mode)."
    echo "  --image-storage STORAGE_ID  Proxmox storage ID for storing downloaded CHR images (optional, see note below)."
    echo "  --force-download            Force download of the CHR image even if it already exists locally."
    echo "  --start                     Start VM after creation (default: ${DEFAULT_START_VM})."
    echo "  --add-tags TAGS             Comma-separated list of additional tags for the VM."
    echo ""
    echo "Note on --image-storage:"
    echo "  If --image-storage is provided and points to a 'dir' or 'nfs' type storage with 'iso' or 'vztmpl' content,"
    echo "  the downloaded CHR image (.img and .zip) will be stored in an 'os4dev_images' subdirectory on that storage"
    echo "  and reused on subsequent runs (unless --force-download is specified)."
    echo "  Otherwise, a temporary system directory will be used, and images will not be kept."
    echo ""
    echo "Examples:"
    echo ""
    echo "  1. Simple interactive mode (prompts for all settings, English if whiptail is available):"
    echo "     sudo $(basename "$0") -i"
    echo ""
    echo "  2. Non-interactive with specific CHR version (URL will be constructed):"
    echo "     sudo $(basename "$0") --storage local-lvm --chr-version 7.14.2" 
    echo ""
    echo "  3. Non-interactive mode with many parameters specified (using specific CHR version):"
    echo "     sudo $(basename "$0") \\"
    echo "       --vmid 777 \\"
    echo "       --hostname my-mikrotik-gw \\"
    echo "       --chr-version 7.15.1 \\" 
    echo "       --cores 2 \\"
    echo "       --ram 512 \\"
    echo "       --bridge vmbr1 \\"
    echo "       --vlan 100 \\"
    echo "       --storage tank-lvm \\"
    echo "       --image-storage nas-iso-storage \\"
    echo "       --add-tags gateway,firewall,networking \\"
    echo "       --start"
    echo ""
    echo "  4. Force re-download of the image, even if it exists on '--image-storage' (non-interactive):"
    echo "     sudo $(basename "$0") --storage local-lvm --image-storage nas-iso-storage --force-download --chr-version ${DEFAULT_CHR_VERSION}"
    echo ""
}

# UA: --- Функція для генерації випадкової MAC-адреси ---
# EN: --- Function to generate a random MAC address ---
generate_mac() {
    echo '00:60:2F:'$(od -An -N3 -t x1 /dev/urandom | awk '{print $1":"$2":"$3}') | tr '[:lower:]' '[:upper:]'
}

# UA: --- Функція для отримання наступного доступного VMID ---
# EN: --- Function to get the next available VMID ---
get_valid_nextid() {
    local try_id
    local prefix="$1" 
    if ! command -v pvesh >/dev/null; then 
        log_warn "EN: 'pvesh' command not found. Cannot reliably determine next VMID via API. Using prefix + 01."
        echo "${prefix}01"
        return
    fi
    try_id=$(pvesh get /cluster/nextid 2>/dev/null || echo "${prefix}00") 
    if ! [[ "$try_id" =~ ^[0-9]+$ ]] || [ "$try_id" -lt 100 ]; then
        try_id="${prefix}00" 
    fi

    if [[ ! "$try_id" == "${prefix}"* ]]; then
         try_id="${prefix}00"
    fi

    while true; do
        try_id=$((try_id + 1)) 
        local current_check_id="$try_id" 

        if [ -f "/etc/pve/qemu-server/${current_check_id}.conf" ] || [ -f "/etc/pve/lxc/${current_check_id}.conf" ]; then
            continue 
        fi
        echo "$current_check_id" 
        return 
    done
}


# UA: --- Розбір аргументів командного рядка ---
# EN: --- Parse command-line arguments ---
parse_arguments() {
    if [ $# -eq 0 ]; then 
        INTERACTIVE_MODE="true"
        log_info "No arguments provided. Attempting to run in interactive mode if whiptail is available."
    fi

    while [[ $# -gt 0 ]]; do 
        case "$1" in 
            -h|--help) 
                show_help 
                exit 0    
                ;;
            -i|--interactive) 
                INTERACTIVE_MODE="true" 
                shift 
                ;;
            --lang) 
                if [[ "$2" == "en" || "$2" == "uk" ]]; then
                    SCRIPT_LANG="$2"
                else
                    log_warn "Invalid language code '$2'. Using default '${DEFAULT_SCRIPT_LANG}'."
                fi
                shift 2
                ;;
            --chr-version) 
                CHR_VERSION="$2"
                shift 2
                ;;
            --image-base-url) 
                IMAGE_BASE_URL="$2"
                shift 2
                ;;
            --vmid) VMID="$2"; shift 2 ;;
            --hn|--hostname) HN="$2"; shift 2 ;;
            --cores) CORE_COUNT="$2"; shift 2 ;;
            --ram) RAM_SIZE="$2"; shift 2 ;;
            --bridge) BRIDGE="$2"; shift 2 ;;
            --mac) MAC_ADDRESS="$2"; shift 2 ;;
            --vlan) VLAN_TAG="$2"; shift 2 ;;
            --mtu) MTU_SIZE="$2"; shift 2 ;;
            --storage) PROXMOX_STORAGE="$2"; shift 2 ;;
            --image-storage) IMAGE_STORAGE="$2"; shift 2;;
            --force-download) FORCE_DOWNLOAD="yes"; shift;;
            --start) START_VM="yes"; shift ;;
            --add-tags) ADDITIONAL_TAGS="$2"; shift 2 ;;
            --download-dir) 
                log_warn "Option --download-dir is deprecated. Please use --image-storage instead."
                if [[ -z "$IMAGE_STORAGE" ]]; then IMAGE_STORAGE="$2"; fi
                shift 2 ;;
            *)  
                log_error "Unknown option: $1" 
                show_help 
                exit 1    
                ;;
        esac
    done
}

# UA: --- Фіналізація налаштувань: заповнення відсутніх значень або запуск whiptail ---
# EN: --- Fill missing settings with defaults or run whiptail ---
finalize_settings() {
    if [[ -z "$SCRIPT_LANG" ]]; then
        SCRIPT_LANG="$DEFAULT_SCRIPT_LANG"
    fi
    log_info "Selected script language for interactive prompts: $SCRIPT_LANG"

    local backtitle_text="Proxmox OS4DEV Scripts" 
    local vmid_prompt_text_uk="Встановіть ID Віртуальної Машини"
    local vmid_prompt_text_en="Set Virtual Machine ID"
    local vmid_title_text_uk="ID ВІРТУАЛЬНОЇ МАШИНИ"
    local vmid_title_text_en="VIRTUAL MACHINE ID"
    local hn_prompt_text_uk="Встановіть Ім'я Хоста"
    local hn_prompt_text_en="Set Hostname"
    local hn_title_text_uk="ІМ'Я ХОСТА"
    local hn_title_text_en="HOSTNAME"
    local cores_prompt_text_uk="Виділіть Ядра ЦП"
    local cores_prompt_text_en="Allocate CPU Cores"
    local cores_title_text_uk="КІЛЬКІСТЬ ЯДЕР"
    local cores_title_text_en="CORE COUNT"
    local ram_prompt_text_uk="Виділіть RAM в МБ"
    local ram_prompt_text_en="Allocate RAM in MB"
    local ram_title_text_uk="ОПЕРАТИВНА ПАМ'ЯТЬ"
    local ram_title_text_en="RAM"
    local bridge_prompt_text_uk="Встановіть Мережевий Міст"
    local bridge_prompt_text_en="Set Network Bridge"
    local bridge_title_text_uk="МІСТ"
    local bridge_title_text_en="BRIDGE"
    local mac_prompt_text_uk="Встановіть MAC-адресу"
    local mac_prompt_text_en="Set MAC Address"
    local mac_title_text_uk="MAC-АДРЕСА"
    local mac_title_text_en="MAC ADDRESS"
    local vlan_prompt_text_uk="Встановіть VLAN (залиште порожнім для значення за замовчуванням)"
    local vlan_prompt_text_en="Set VLAN (leave blank for default)"
    local vlan_title_text_uk="VLAN"
    local vlan_title_text_en="VLAN"
    local mtu_prompt_text_uk="Встановіть Розмір MTU Інтерфейсу (залиште порожнім для значення за замовчуванням)"
    local mtu_prompt_text_en="Set Interface MTU Size (leave blank for default)"
    local mtu_title_text_uk="РОЗМІР MTU"
    local mtu_title_text_en="MTU SIZE"
    local chr_version_prompt_text_uk="Вкажіть версію RouterOS CHR (напр. ${DEFAULT_CHR_VERSION})"
    local chr_version_prompt_text_en="Specify RouterOS CHR version (e.g. ${DEFAULT_CHR_VERSION})"
    local chr_version_title_text_uk="ВЕРСІЯ ROUTEROS CHR"
    local chr_version_title_text_en="ROUTEROS CHR VERSION"
    local start_vm_prompt_text_uk="Запустити ВМ після завершення?"
    local start_vm_prompt_text_en="Start VM when completed?"
    local start_vm_title_text_uk="ЗАПУСК ВІРТУАЛЬНОЇ МАШИНИ"
    local start_vm_title_text_en="START VIRTUAL MACHINE"

    # CHR Version
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$CHR_VERSION" ]]; then
        local prompt_text="$chr_version_prompt_text_en"
        local title_text="$chr_version_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$chr_version_prompt_text_uk"
            title_text="$chr_version_title_text_uk"
        fi
        CHR_VERSION=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "$DEFAULT_CHR_VERSION" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$CHR_VERSION" ]]; then
        CHR_VERSION="$DEFAULT_CHR_VERSION"
    fi

    # Image Base URL
    if [[ -z "$IMAGE_BASE_URL" ]]; then
        IMAGE_BASE_URL="$DEFAULT_IMAGE_BASE_URL"
    fi

    # Construct final IMAGE_URL
    IMAGE_URL="${IMAGE_BASE_URL}/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
    
    # VMID
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$VMID" ]]; then 
        local prompt_text="$vmid_prompt_text_en"
        local title_text="$vmid_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$vmid_prompt_text_uk"
            title_text="$vmid_title_text_uk"
        fi
        VMID=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "$(get_valid_nextid "$DEFAULT_VMID_PREFIX")" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$VMID" ]]; then 
        VMID=$(get_valid_nextid "$DEFAULT_VMID_PREFIX")
    fi

    # Hostname
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$HN" ]]; then
        local prompt_text="$hn_prompt_text_en"
        local title_text="$hn_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$hn_prompt_text_uk"
            title_text="$hn_title_text_uk"
        fi
        HN=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "${DEFAULT_HN_PREFIX}-${VMID}" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$HN" ]]; then
        HN="${DEFAULT_HN_PREFIX}-${VMID}"
    fi
    HN=$(echo "${HN,,}" | tr -d '[:space:]') 

    # Cores
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$CORE_COUNT" ]]; then
        local prompt_text="$cores_prompt_text_en"
        local title_text="$cores_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$cores_prompt_text_uk"
            title_text="$cores_title_text_uk"
        fi
        CORE_COUNT=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "$DEFAULT_CORES" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$CORE_COUNT" ]]; then
        CORE_COUNT="$DEFAULT_CORES"
    fi

    # RAM
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$RAM_SIZE" ]]; then
        local prompt_text="$ram_prompt_text_en"
        local title_text="$ram_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$ram_prompt_text_uk"
            title_text="$ram_title_text_uk"
        fi
        RAM_SIZE=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "$DEFAULT_RAM_MB" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$RAM_SIZE" ]]; then
        RAM_SIZE="$DEFAULT_RAM_MB"
    fi

    # Bridge
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$BRIDGE" ]]; then
        local prompt_text="$bridge_prompt_text_en"
        local title_text="$bridge_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$bridge_prompt_text_uk"
            title_text="$bridge_title_text_uk"
        fi
        BRIDGE=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "$DEFAULT_BRIDGE" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$BRIDGE" ]]; then
        BRIDGE="$DEFAULT_BRIDGE"
    fi

    # MAC Address
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$MAC_ADDRESS" ]]; then
        local prompt_text="$mac_prompt_text_en"
        local title_text="$mac_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$mac_prompt_text_uk"
            title_text="$mac_title_text_uk"
        fi
        MAC_ADDRESS=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 58 "$(generate_mac)" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$MAC_ADDRESS" ]]; then
        MAC_ADDRESS=$(generate_mac)
    fi

    # VLAN
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$VLAN_TAG" ]]; then
        local prompt_text="$vlan_prompt_text_en"
        local title_text="$vlan_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$vlan_prompt_text_uk"
            title_text="$vlan_title_text_uk"
        fi
        VLAN_TAG=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 70 "$DEFAULT_VLAN" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$VLAN_TAG" ]]; then
        VLAN_TAG="$DEFAULT_VLAN"
    fi

    # MTU
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$MTU_SIZE" ]]; then
        local prompt_text="$mtu_prompt_text_en"
        local title_text="$mtu_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$mtu_prompt_text_uk"
            title_text="$mtu_title_text_uk"
        fi
        MTU_SIZE=$(whiptail --backtitle "$backtitle_text" --inputbox "$prompt_text" 8 70 "$DEFAULT_MTU" --title "$title_text" 3>&1 1>&2 2>&3) || { log_error "User cancelled."; exit 1; }
    elif [[ -z "$MTU_SIZE" ]]; then
        MTU_SIZE="$DEFAULT_MTU"
    fi
    
    # Storage for VM Disk (Required for non-interactive)
    if [[ "$INTERACTIVE_MODE" == "false" && -z "$PROXMOX_STORAGE" ]]; then 
        log_error "Proxmox storage ID for VM disk must be specified with --storage <ID> when not in interactive mode."
        show_help 
        exit 1
    fi
    
    # Force Download
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$FORCE_DOWNLOAD" ]]; then 
        local prompt_text_uk="Примусово завантажити образ, навіть якщо він існує?"
        local prompt_text_en="Force download image even if it exists?"
        local title_text_uk="ПРИМУСОВЕ ЗАВАНТАЖЕННЯ"
        local title_text_en="FORCE DOWNLOAD"
        local current_prompt="$prompt_text_en"
        local current_title="$title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            current_prompt="$prompt_text_uk"
            current_title="$title_text_uk"
        fi
        if (whiptail --backtitle "$backtitle_text" --title "$current_title" --yesno "$current_prompt" 10 60); then
            FORCE_DOWNLOAD="yes"
        else
            FORCE_DOWNLOAD="no"
        fi
    elif [[ -z "$FORCE_DOWNLOAD" ]]; then 
         FORCE_DOWNLOAD="$DEFAULT_FORCE_DOWNLOAD"
    fi

    # Start VM
    if [[ "$INTERACTIVE_MODE" == "true" && -z "$START_VM" ]]; then 
        local prompt_text="$start_vm_prompt_text_en"
        local title_text="$start_vm_title_text_en"
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            prompt_text="$start_vm_prompt_text_uk"
            title_text="$start_vm_title_text_uk"
        fi
        if (whiptail --backtitle "$backtitle_text" --title "$title_text" --yesno "$prompt_text" 10 58); then
            START_VM="yes"
        else
            START_VM="no"
        fi
    elif [[ -z "$START_VM" ]]; then 
         START_VM="$DEFAULT_START_VM"
    fi

    log_info "--- Final Configuration ---"
    log_info "VMID: $VMID"
    log_info "Hostname: $HN"
    log_info "Cores: $CORE_COUNT"
    log_info "RAM: ${RAM_SIZE}MB"
    log_info "Bridge: $BRIDGE"
    log_info "MAC Address: $MAC_ADDRESS"
    log_info "VLAN Tag: ${VLAN_TAG:-None}" 
    log_info "MTU Size: ${MTU_SIZE:-Default}"
    log_info "CHR Version:                 $CHR_VERSION"
    log_info "Image Base URL:              $IMAGE_BASE_URL"
    log_info "Constructed Image URL:       $IMAGE_URL"
    log_info "Image Storage for CHR:       ${IMAGE_STORAGE:-Autodetect or TempDir}"
    log_info "Force Download:              $FORCE_DOWNLOAD"
    log_info "VM Disk Storage Pool:        ${PROXMOX_STORAGE:-To be selected/validated}"
    log_info "Start VM on completion:      $START_VM"
    log_info "Base Tags:                   $DEFAULT_TAGS"
    log_info "Additional Tags:             ${ADDITIONAL_TAGS:-None}"
    log_info "--------------------------------------------------------------------" 
}


# UA: --- Перевірка вимог скрипту ---
# EN: --- Check script requirements ---
check_requirements() {
    log_info "Checking requirements..."
    local missing_utils=0
    local utils_to_check=("curl" "qm" "pvesm" "gunzip" "awk" "grep" "sed" "od" "cut" "head" "mktemp" "tput")
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then 
        utils_to_check+=("whiptail")
    fi

    for util in "${utils_to_check[@]}"; do
        if ! command -v "$util" &> /dev/null; then 
            log_error "Required utility '$util' is not installed or not in PATH." && missing_utils=$((missing_utils + 1))
        fi
    done
    if [ "$missing_utils" -gt 0 ]; then
        log_error "Please install missing utilities and try again." && exit 1
    fi

    if ! pveversion | grep -Eq "pve-manager/(8\.[1-9]|[9-99]\.)"; then 
        log_error "This script requires Proxmox VE version 8.1 or later."
        exit 1
    fi
    log_success "Requirements met."
}

# UA: --- Вибір сховища Proxmox VE для диска ВМ ---
# EN: --- Select Proxmox VE storage pool for VM disk ---
get_storage_pool() {
    log_info "Validating Proxmox VE storage for VM disk..." 
    local storage_menu=() 
    local item=""          
    local offset=2         
    local msg_max_length=0 
    local backtitle_text="Proxmox OS4DEV Scripts" 
    
    if ! command -v pvesm &> /dev/null; then 
        log_error "'pvesm' command not found. Cannot list storage pools." 
        return 1 
    fi

    local pvesm_output 
    if ! pvesm_output=$(pvesm status -content images 2>/dev/null); then 
        log_error "Failed to get storage status from pvesm." 
        return 1
    fi
    
    if [[ -z "$pvesm_output" || $(echo "$pvesm_output" | wc -l) -lt 2 ]]; then 
        log_warn "No storage pools found that support 'images' content type." 
        return 1
    fi

    while read -r line; do
        local tag type free_gb total_gb 
        tag=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{printf "%-10s", $2}') 
        total_gb=$(echo "$line" | awk '{val=$4/1024/1024; printf "%.2f", val}') 
        free_gb=$(echo "$line" | awk '{val=$5/1024/1024; printf "%.2f", val}')  
        
        local item_text_uk="Тип: $type, Вільно: ${free_gb}ГБ / Всього: ${total_gb}ГБ"
        local item_text_en="Type: $type, Free: ${free_gb}GB / Total: ${total_gb}GB"
        item="$item_text_en" 
        if [[ "$SCRIPT_LANG" == "uk" ]]; then
            item="$item_text_uk" 
        fi
        
        if [[ $((${#item} + $offset)) -gt ${msg_max_length:-0} ]]; then
            msg_max_length=$((${#item} + $offset))
        fi
        storage_menu+=("$tag" "$item" "OFF")
    done < <(echo "$pvesm_output" | awk 'NR>1') 


    if [ ${#storage_menu[@]} -eq 0 ]; then 
        log_warn "No suitable storage pools found that can store VM images." 
        return 1
    fi

    if [[ "$INTERACTIVE_MODE" == "true" && -z "$PROXMOX_STORAGE" ]]; then 
        if [ $((${#storage_menu[@]} / 3)) -eq 1 ]; then 
            PROXMOX_STORAGE=${storage_menu[0]}
            log_info "Only one suitable storage pool for VM disk found: ${PROXMOX_STORAGE}. Using it." 
        else 
            local radiolist_prompt_uk="Оберіть сховище для диска ВМ Mikrotik CHR:\n\n"
            local radiolist_prompt_en="Select a storage pool for the Mikrotik CHR VM disk:\n\n"
            local radiolist_title_uk="Вибір Сховища для Диска ВМ"
            local radiolist_title_en="VM Disk Storage Pool Selection"

            local prompt_text="$radiolist_prompt_en" 
            local title_text="$radiolist_title_en"   
            if [[ "$SCRIPT_LANG" == "uk" ]]; then
                prompt_text="$radiolist_prompt_uk"
                title_text="$radiolist_title_uk"
            fi

            PROXMOX_STORAGE=$(whiptail --backtitle "$backtitle_text" --title "$title_text" --radiolist \
                "$prompt_text" \
                20 $((msg_max_length + 20)) "$((${#storage_menu[@]}/3))" \
                "${storage_menu[@]}" 3>&1 1>&2 2>&3) \
                || { log_error "VM disk storage selection cancelled."; return 1; } 
        fi
    elif [[ -n "$PROXMOX_STORAGE" ]]; then 
        local found=0 
        for (( i=0; i<${#storage_menu[@]}; i+=3 )); do 
            if [[ "${storage_menu[i]}" == "$PROXMOX_STORAGE" ]]; then 
                found=1; break 
            fi
        done
        if [[ "$found" -eq 0 ]]; then 
            log_error "Specified VM disk storage '$PROXMOX_STORAGE' is not valid or does not support 'images' content." 
            log_info "Available storages for VM disks: $(echo "$pvesm_output" | awk 'NR>1 {print $1}' | tr '\n' ' ')" 
            return 1
        fi
        log_info "Using specified storage pool for VM disk: $PROXMOX_STORAGE" 
    fi
    log_success "Using storage pool for VM disk: $PROXMOX_STORAGE" 
    return 0 
}

# UA: --- Визначення/перевірка сховища для завантажених образів CHR ---
# EN: --- Determine/validate storage for downloaded CHR images ---
get_iso_storage_for_images() {
    log_info "Determining storage for CHR images..." 
    local use_persistent_storage=false 

    if [[ -n "$IMAGE_STORAGE" ]]; then 
        log_info "User specified image storage: $IMAGE_STORAGE" 
        if ! pvesm status -storage "$IMAGE_STORAGE" > /dev/null 2>&1; then
            log_warn "Specified image storage '$IMAGE_STORAGE' does not exist. Will use temporary directory." 
        else
            local storage_info
            storage_info=$(pvesm status -storage "$IMAGE_STORAGE" | awk 'NR>1 {print $2 " " $6}')
            IMAGE_STORAGE_TYPE=$(echo "$storage_info" | awk '{print $1}')
            local content_types 
            content_types=$(echo "$storage_info" | awk '{print $2}')

            if [[ "$IMAGE_STORAGE_TYPE" != "dir" && "$IMAGE_STORAGE_TYPE" != "nfs" ]]; then 
                log_warn "Specified image storage '$IMAGE_STORAGE' is type '$IMAGE_STORAGE_TYPE'. Must be 'dir' or 'nfs' to store images persistently. Will use temporary directory." 
            elif ! echo "$content_types" | grep -Eq '(iso|vztmpl)'; then
                log_warn "Specified image storage '$IMAGE_STORAGE' (type: $IMAGE_STORAGE_TYPE) does not list 'iso' or 'vztmpl' in its content types. Falling back to temporary directory."
            else
                IMAGE_STORAGE_PATH=$(pvesm status -storage "$IMAGE_STORAGE" | awk 'NR>1 {print $NF}' | sed -n 's/.*path=\([^,]*\).*/\1/p')
                if [[ -z "$IMAGE_STORAGE_PATH" || ! -d "$IMAGE_STORAGE_PATH" ]]; then
                    log_warn "Could not determine or access path for specified image storage '$IMAGE_STORAGE'. Will use temporary directory." 
                else
                    use_persistent_storage=true
                    log_success "Will use user-specified image storage '$IMAGE_STORAGE' (type: $IMAGE_STORAGE_TYPE) at path '$IMAGE_STORAGE_PATH'." 
                fi
            fi
        fi
    else
        log_info "No persistent image storage specified (--image-storage). Images will be downloaded to temporary directory '$TEMP_DIR' and not kept." 
    fi

    if [[ "$use_persistent_storage" == "true" ]]; then
        IMAGE_STORAGE_PATH="${IMAGE_STORAGE_PATH}/os4dev_images" 
        if [[ ! -d "$IMAGE_STORAGE_PATH" ]]; then 
            log_info "Creating image subdirectory: $IMAGE_STORAGE_PATH" 
            if ! mkdir -p "$IMAGE_STORAGE_PATH"; then 
                log_warn "Failed to create image subdirectory '$IMAGE_STORAGE_PATH'. Using temporary directory '$TEMP_DIR' instead." 
                IMAGE_STORAGE_PATH="$TEMP_DIR"
                IMAGE_STORAGE="" 
            fi
        fi
    else
        IMAGE_STORAGE_PATH="$TEMP_DIR"
        if [[ -n "$IMAGE_STORAGE" && "$use_persistent_storage" == "false" ]]; then 
            log_info "Image storage '$IMAGE_STORAGE' was unsuitable, operations will use '$TEMP_DIR'."
            IMAGE_STORAGE="" 
        fi
    fi
    
    if [[ "$IMAGE_STORAGE_PATH" == "$TEMP_DIR" ]]; then
        log_info "Image operations (download, extraction) will use temporary directory: $IMAGE_STORAGE_PATH"
    else
        log_info "Image operations (download, extraction, storage) will use persistent path: $IMAGE_STORAGE_PATH"
    fi

    return 0
}


# UA: --- Завантаження та розпакування образу Mikrotik CHR ---
# EN: --- Download and extract Mikrotik CHR image ---
download_and_extract_image() {
    local image_basename_zip
    local image_basename_img
    image_basename_zip=$(basename "$IMAGE_URL")
    image_basename_img=$(basename "${IMAGE_URL%.zip}") 

    LOCAL_IMAGE_ZIP_PATH="${IMAGE_STORAGE_PATH}/${image_basename_zip}"
    FINAL_IMAGE_PATH_ON_STORAGE="${IMAGE_STORAGE_PATH}/${image_basename_img}"

    log_info "Target path for CHR image: $FINAL_IMAGE_PATH_ON_STORAGE"

    if [[ "$FORCE_DOWNLOAD" == "yes" ]]; then
        log_info "Force download is enabled. Will attempt to download the image regardless of local copies."
        log_info "Removing existing image files (if any) due to --force-download: $FINAL_IMAGE_PATH_ON_STORAGE and $LOCAL_IMAGE_ZIP_PATH"
        rm -f "$FINAL_IMAGE_PATH_ON_STORAGE" "$LOCAL_IMAGE_ZIP_PATH"
    fi

    if [[ -f "$FINAL_IMAGE_PATH_ON_STORAGE" ]]; then
        log_success "CHR image already exists at: $FINAL_IMAGE_PATH_ON_STORAGE. Skipping download and extraction."
        return 0
    fi

    if [[ -f "$LOCAL_IMAGE_ZIP_PATH" ]]; then
        log_info "CHR ZIP archive found at: $LOCAL_IMAGE_ZIP_PATH. Attempting to extract..."
    else
        log_info "Downloading Mikrotik CHR image from: $IMAGE_URL to $LOCAL_IMAGE_ZIP_PATH"
        if curl --progress-bar -fSL -o "$LOCAL_IMAGE_ZIP_PATH" "$IMAGE_URL"; then 
            echo "" 
            log_success "Downloaded: $(basename "$LOCAL_IMAGE_ZIP_PATH")"
        else
            log_error "Failed to download image from $IMAGE_URL."
            rm -f "$LOCAL_IMAGE_ZIP_PATH" 
            return 1
        fi
    fi

    log_info "Extracting image: $(basename "$LOCAL_IMAGE_ZIP_PATH") to $IMAGE_STORAGE_PATH"
    if gunzip -f -S .zip -c "$LOCAL_IMAGE_ZIP_PATH" > "$FINAL_IMAGE_PATH_ON_STORAGE"; then 
        log_success "Extracted image to: $FINAL_IMAGE_PATH_ON_STORAGE"
        if [[ "$IMAGE_STORAGE_PATH" == "$TEMP_DIR" ]]; then
            log_info "Removing temporary ZIP archive: $LOCAL_IMAGE_ZIP_PATH"
            rm -f "$LOCAL_IMAGE_ZIP_PATH"
        elif [[ "$FORCE_DOWNLOAD" == "yes" && "$IMAGE_STORAGE_PATH" != "$TEMP_DIR" ]]; then
            log_info "Keeping newly downloaded ZIP archive on persistent storage: $LOCAL_IMAGE_ZIP_PATH"
        else
            log_info "Keeping ZIP archive on persistent storage: $LOCAL_IMAGE_ZIP_PATH"
        fi
    else
        log_error "Failed to extract image $(basename "$LOCAL_IMAGE_ZIP_PATH")."
        rm -f "$FINAL_IMAGE_PATH_ON_STORAGE" 
        if [[ "$IMAGE_STORAGE_PATH" == "$TEMP_DIR" ]]; then
             rm -f "$LOCAL_IMAGE_ZIP_PATH"
        fi
        return 1
    fi
    return 0
}

# UA: --- Створення та налаштування ВМ ---
# EN: --- Create and configure the VM ---
create_and_configure_vm() {
    log_info "Creating Mikrotik RouterOS CHR VM (ID: $VMID, Name: $HN)..."

    local disk_ext="" 
    local disk_ref_path_segment="" 
    local disk_import_format_option="" 
    local storage_type
    storage_type=$(pvesm status -storage "$PROXMOX_STORAGE" | awk 'NR>1 {print $2}') 

    case "$storage_type" in
        nfs|dir) 
            disk_ext=".qcow2"
            disk_ref_path_segment="$VMID/" 
            #disk_import_format_option="-format qcow2"
            disk_import_format_option=""
            ;;
        btrfs) 
            disk_ext=".raw"
            disk_ref_path_segment="$VMID/"
            disk_import_format_option="-format raw"
            ;;
        lvm|lvmthin|zfspool) 
            disk_ext="" 
            disk_ref_path_segment="" 
            disk_import_format_option="-format raw"
            ;;
        *) 
            log_warn "Unsupported storage type '$storage_type' for disk extension/path guessing. Assuming raw."
            disk_ext=".raw"
            disk_import_format_option="-format raw"
            ;;
    esac
    
    local net_config="virtio,bridge=${BRIDGE},macaddr=${MAC_ADDRESS}" 
    if [[ -n "$VLAN_TAG" ]]; then net_config+=",tag=${VLAN_TAG}"; fi 
    if [[ -n "$MTU_SIZE" ]]; then net_config+=",mtu=${MTU_SIZE}"; fi 

    FINAL_TAGS="$DEFAULT_TAGS"
    if [[ -n "$ADDITIONAL_TAGS" ]]; then
        FINAL_TAGS="${FINAL_TAGS},${ADDITIONAL_TAGS}"
    fi
    FINAL_TAGS=$(echo "$FINAL_TAGS" | sed 's/,,*/,/g; s/^,//; s/,$//') 

    if qm create "$VMID" \
        --name "$HN" \
        --ostype l26 \
        --cores "$CORE_COUNT" \
        --memory "$RAM_SIZE" \
        --net0 "$net_config" \
        --scsihw virtio-scsi-pci \
        --tablet 0 \
        --localtime 1 \
        --onboot 1 \
        --tags "$FINAL_TAGS"; then 
        log_success "VM $VMID ($HN) created."
    else
        log_error "Failed to create VM $VMID."
        return 1
    fi

    log_info "Importing disk from $FINAL_IMAGE_PATH_ON_STORAGE to storage $PROXMOX_STORAGE for VM $VMID..."
    if qm importdisk "$VMID" "$FINAL_IMAGE_PATH_ON_STORAGE" "$PROXMOX_STORAGE" ${disk_import_format_option:+"$disk_import_format_option"}; then
        log_success "Disk imported successfully."
    else
        log_error "Failed to import disk for VM $VMID."
        qm destroy "$VMID" --purge --destroy-unreferenced-disks 1 || log_warn "Could not cleanup VM $VMID after failed disk import."
        return 1
    fi
    
    local unused_disk_id
    unused_disk_id=$(qm config "$VMID" | grep unused | cut -d':' -f1 | head -n1) 
    if [[ -z "$unused_disk_id" ]]; then 
        log_error "No unused disk found after import for VM $VMID."
        return 1
    fi
    
    local volume_ref_for_scsi0
    volume_ref_for_scsi0=$(qm config "$VMID" | grep "^${unused_disk_id}:" | sed -E "s/^${unused_disk_id}:[[:space:]]*([^,]+).*/\1/")


    log_info "Attaching imported disk as scsi0 and setting boot order..."
    if qm set "$VMID" --scsi0 "${volume_ref_for_scsi0}" --boot order=scsi0; then
        log_success "Disk scsi0 configured and boot order set."
    else
        log_error "Failed to configure scsi0 or set boot order for VM $VMID."
        return 1
    fi
    
    local vm_description_uk="<div align='center'><a href='https://github.com/os4-dev/infra-commons'><img src='https://raw.githubusercontent.com/os4-dev/infra-commons/main/docs/assets/logo.png' width='81'/></a><br/><b>Mikrotik RouterOS CHR</b><br/>Розгорнуто за допомогою скрипту Proxmox OS4DEV Scripts.<br/>Оригінальний скрипт від tteck (community-scripts).</div>"
    local vm_description_en="<div align='center'><a href='https://github.com/os4-dev/infra-commons'><img src='https://raw.githubusercontent.com/os4-dev/infra-commons/main/docs/assets/logo.png' width='81'/></a><br/><b>Mikrotik RouterOS CHR</b><br/>Deployed by Proxmox OS4DEV Scripts.<br/>Original script by tteck (community-scripts).</div>"
    local final_vm_description="$vm_description_en" 
    if [[ "$SCRIPT_LANG" == "uk" ]]; then
        final_vm_description="$vm_description_uk"
    fi
    
    if qm set "$VMID" --description "$final_vm_description"; then 
        log_success "VM description updated."
    else
        log_warn "Failed to update VM description. (Non-fatal)"
    fi
    return 0 
}

# UA: --- Основне виконання скрипту ---
# EN: --- Main script execution ---
main() {
    # UA: Крок 1: Розбір аргументів командного рядка
    parse_arguments "$@" 
    
    # UA: Крок 2: Фіналізація налаштувань
    finalize_settings 
    
    # UA: Крок 3: Перевірка системних вимог
    check_requirements 

    # UA: Крок 4: Вибір або перевірка сховища Proxmox VE ДЛЯ ДИСКА ВМ
    if ! get_storage_pool; then 
        log_error "Failed to determine a valid VM disk storage pool. Exiting." 
        exit 1
    fi

    # UA: Крок 5: Створення тимчасової директорії (завжди створюється, але може не використовуватися для образу)
    # UA: та визначення/перевірка сховища для образів CHR
    TEMP_DIR=$(mktemp -d) 
    log_info "Temporary directory created: $TEMP_DIR (may not be used for image if --image-storage is set)" 

    if ! get_iso_storage_for_images; then 
        log_error "Failed to determine a storage for CHR images. Exiting."
        exit 1
    fi
    
    # UA: Крок 6: Завантаження та розпакування образу Mikrotik CHR
    if ! download_and_extract_image; then 
        log_error "Failed to download or extract Mikrotik image. Exiting." 
        exit 1
    fi

    # UA: Крок 7: Створення та налаштування віртуальної машини
    if ! create_and_configure_vm; then 
        log_error "Failed to create or configure VM. Exiting." 
        exit 1 
    fi

    # UA: Крок 8: Запуск віртуальної машини (якщо вказано)
    if [[ "$START_VM" == "yes" ]]; then 
        log_info "Starting VM $VMID..." 
        if qm start "$VMID"; then
            log_success "VM $VMID started successfully." 
        else
            log_error "Failed to start VM $VMID." 
        fi
    fi
    
    # UA: Крок 9: Фінальні повідомлення для користувача
    log_success "Mikrotik RouterOS CHR VM (ID: $VMID, Name: $HN) deployment completed successfully!" 
    log_info "You might need to wait a few minutes for the VM to fully boot and become accessible." 
    log_info "Default credentials for Mikrotik CHR: admin (no password - set one on first login)." 
}

# UA: --- Запуск основної функції ---
# EN: --- Run the main function ---
main "$@" 

# UA: Trap EXIT автоматично викличе `cleanup_temp_dir` для очищення тимчасової директорії.
# EN: Trap EXIT will handle `cleanup_temp_dir`.
exit 0
