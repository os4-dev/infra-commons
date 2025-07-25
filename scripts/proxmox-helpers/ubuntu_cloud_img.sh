#!/usr/bin/env bash

# UA: Скрипт для створення шаблонів Proxmox з гнучким керуванням сховищами та "розумним" оновленням образів.
# EN: Script to create Proxmox templates with flexible storage management and "smart" image updating.

set -e -u -o pipefail

# --- UA: Кольори та атрибути для виводу ---
# --- EN: Colors and attributes for output ---
C_RESET=$(tput sgr0 2>/dev/null || echo '\033[0m')
C_RED=$(tput setaf 1 2>/dev/null || echo '\033[0;31m')
C_GREEN=$(tput setaf 2 2>/dev/null || echo '\033[0;32m')
C_YELLOW=$(tput setaf 3 2>/dev/null || echo '\033[0;33m')
C_BLUE=$(tput setaf 4 2>/dev/null || echo '\033[0;34m')

# --- UA: Функції для логування ---
# --- EN: Logging functions ---
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; }

# --- UA: Значення за замовчуванням ---
# --- EN: Default values ---
DEFAULT_USER="dev4pve"
DEFAULT_UBUNTU_CODENAME="noble"
DEFAULT_UBUNTU_ARCH="amd64"
DEFAULT_IMAGE_BASE_URL="https://cloud-images.ubuntu.com"
DEFAULT_VMID_PREFIX="90"
DEFAULT_TEMPLATE_NAME_PREFIX="ubuntu"
DEFAULT_VM_CORES="2"
DEFAULT_VM_MEMORY="2048"
DEFAULT_VM_DISK_SIZE="32G"
DEFAULT_SSH_PUB_KEY_FILE="/root/.ssh/id_rsa.pub"
DEFAULT_BASE_TAGS="ubuntu"

# --- UA: Робочі змінні ---
# --- EN: Working variables ---
VM_USER=""
UBUNTU_CODENAME=""
SSH_PUB_KEY_FILE=""
DISK_STORAGE=""
SNIPPETS_STORAGE=""
IMAGES_STORAGE=""
TEMP_VM_ID=""
FINAL_TEMPLATE_NAME=""
VM_CORES=""
VM_MEMORY=""
VM_DISK_SIZE=""
VM_BRIDGE=""
PROXMOX_NODE=""
DOWNLOAD_DIR=""
LOCAL_IMAGE_PATH=""
INTERACTIVE_MODE="false"
FORCE_DOWNLOAD="false"
USER_TAGS=""

# --- UA: Функція для виведення довідки ---
# --- EN: Function to display help message ---
show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "This script automates the creation of an Ubuntu cloud-init template for Proxmox VE."
    echo ""
    echo "Options:"
    echo "  -h, --help                  Show this help message and exit."
    echo "  -i, --interactive           Force interactive mode for all settings."
    echo "  -c, --codename CODENAME     Ubuntu version codename to use/download (default: ${DEFAULT_UBUNTU_CODENAME})."
    echo "  -s, --storage STORAGE_ID    Storage for the VM disk (required in non-interactive mode)."
    echo "  --snippets-storage ID       Storage for cloud-init snippets (default: same as --storage)."
    echo "  --images-storage ID         Storage for downloaded cloud images (default: auto-detected 'iso' storage)."
    echo "  --bridge INTERFACE          Network bridge or SDN VNet for the VM."
    echo "  --user USERNAME             Admin username to create (default: ${DEFAULT_USER})."
    echo "  --ssh-key-file FILE_PATH    Path to SSH public key file (default: ${DEFAULT_SSH_PUB_KEY_FILE})."
    echo "  --vmid ID                   VM ID for the temporary VM (default: auto-generated)."
    echo "  --template-name NAME        Base name for the final template (default: ubuntu-<codename>)."
    echo "  --tags TAGS                 Comma-separated list of custom tags to add to the template."
    echo "  --force-download            Force download of the latest image, ignoring local versions."
}

# --- UA: Функція для отримання наступного доступного VMID ---
# --- EN: Function to get the next available VMID ---
get_valid_nextid() {
    local try_id prefix="$1"
    # UA: Запитуємо у Proxmox наступний вільний ID.
    # EN: Ask Proxmox for the next available ID.
    try_id=$(pvesh get /cluster/nextid 2>/dev/null || echo "${prefix}00")
    # UA: Перевіряємо, чи отриманий ID валідний, інакше починаємо з базового.
    # EN: Check if the received ID is valid, otherwise start from the base prefix.
    if ! [[ "$try_id" =~ ^[0-9]+$ ]] || [[ ! "$try_id" == "${prefix}"* ]]; then
        try_id="${prefix}00"
    fi
    # UA: Шукаємо перший ID, який не зайнятий ані ВМ, ані контейнером.
    # EN: Find the first ID that is not occupied by either a VM or a container.
    while true; do
        try_id=$((try_id + 1))
        if ! qm status "$try_id" >/dev/null 2>&1 && ! pct status "$try_id" >/dev/null 2>&1; then
            echo "$try_id"
            return
        fi
    done
}

# --- UA: Розбір аргументів командного рядка ---
# --- EN: Parse command-line arguments ---
parse_arguments() {
    # UA: Якщо немає аргументів, вмикаємо інтерактивний режим.
    # EN: If no arguments are provided, enable interactive mode.
    if [ $# -eq 0 ]; then INTERACTIVE_MODE="true"; fi
    # UA: Обробляємо всі передані параметри.
    # EN: Process all provided parameters.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -i|--interactive) INTERACTIVE_MODE="true"; shift ;;
            -c|--codename) UBUNTU_CODENAME="$2"; shift 2 ;;
            -s|--storage) DISK_STORAGE="$2"; shift 2 ;;
            --snippets-storage) SNIPPETS_STORAGE="$2"; shift 2 ;;
            --images-storage) IMAGES_STORAGE="$2"; shift 2 ;;
            --bridge) VM_BRIDGE="$2"; shift 2 ;;
            --user) VM_USER="$2"; shift 2 ;;
            --ssh-key-file) SSH_PUB_KEY_FILE="$2"; shift 2 ;;
            --vmid) TEMP_VM_ID="$2"; shift 2 ;;
            --template-name) FINAL_TEMPLATE_NAME="$2"; shift 2 ;;
            --tags) USER_TAGS="$2"; shift 2 ;;
            --force-download) FORCE_DOWNLOAD="true"; shift ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# --- UA: Функція вибору сховища ---
# --- EN: Storage selection function ---
select_storage() {
    local content_type="$1"
    local prompt_title="$2"
    local provided_storage_id="$3"
    local selected_storage=""

    # UA: Якщо сховище вказано через параметр, валідуємо його.
    # EN: If a storage is specified via a parameter, validate it.
    if [[ -n "$provided_storage_id" ]]; then
        if pvesm status -storage "$provided_storage_id" -content "$content_type" >/dev/null 2>&1; then
            echo "$provided_storage_id"
            return
        else
            log_error "Provided storage '${provided_storage_id}' for ${prompt_title} is invalid or doesn't support '${content_type}'."
            if [[ "$INTERACTIVE_MODE" != "true" ]]; then exit 1; fi
        fi
    fi

    # UA: В інтерактивному режимі показуємо меню вибору.
    # EN: In interactive mode, show a selection menu.
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        local storage_menu=()
        while read -r line; do
            local id type free total
            id=$(echo "$line" | awk '{print $1}')
            type=$(echo "$line" | awk '{print $2}')
            free=$(printf "%.2f" "$(echo "$line" | awk '{print $5/1024/1024}')")
            total=$(printf "%.2f" "$(echo "$line" | awk '{print $4/1024/1024}')")
            storage_menu+=("$id" "Type: $type, Free: ${free}GB / Total: ${total}GB")
        done < <(pvesm status -content "$content_type" | awk 'NR>1')
        
        if [[ ${#storage_menu[@]} -eq 0 ]]; then log_error "No suitable storage found for ${prompt_title}." && exit 1; fi
        
        selected_storage=$(whiptail --title "${prompt_title}" --menu "Select a storage" 20 78 12 "${storage_menu[@]}" 3>&1 1>&2 2>&3) || exit 1
        echo "$selected_storage"
        return
    fi
    
    # UA: В автоматичному режимі обираємо перше доступне сховище.
    # EN: In automatic mode, select the first available storage.
    selected_storage=$(pvesm status -content "$content_type" | awk 'NR==2 {print $1}')
    if [[ -z "$selected_storage" ]]; then log_error "Could not auto-detect a storage for ${prompt_title}." && exit 1; fi
    echo "$selected_storage"
}

# --- UA: Універсальна функція вибору мережевого інтерфейсу ---
# --- EN: Universal network interface selection function ---
select_network_interface() {
    local provided_interface="$1"
    
    # UA: Якщо інтерфейс вказано через параметр, використовуємо його.
    # EN: If an interface is specified via a parameter, use it.
    if [[ -n "$provided_interface" ]]; then
        echo "$provided_interface"
        return
    fi

    # UA: В інтерактивному режимі збираємо і показуємо всі мости та SDN Vnets.
    # EN: In interactive mode, collect and display all bridges and SDN VNets.
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        local net_menu=()
        while read -r bridge; do
            net_menu+=("$bridge" "(Standard Linux Bridge)")
        done < <(pvesh get /nodes/"$(hostname -f)"/network --output-format json | jq -r '.[] | select(.type == "bridge") | .iface')
        
        while read -r vnet; do
            net_menu+=("$vnet" "(SDN Virtual Network)")
        done < <(pvesh get /cluster/sdn/vnets --output-format json | jq -r '.[].vnet' 2>/dev/null || true)

        if [[ ${#net_menu[@]} -eq 0 ]]; then log_error "No network bridges or SDN VNets found." && exit 1; fi
        
        local selected_interface
        selected_interface=$(whiptail --title "Network Interface" --menu "Select a network interface for the VM" 20 78 12 "${net_menu[@]}" 3>&1 1>&2 2>&3) || exit 1
        echo "$selected_interface"
        return
    fi
    
    # UA: В автоматичному режимі шукаємо vmbr0, потім будь-який міст, потім будь-який VNet.
    # EN: In automatic mode, search for vmbr0, then any bridge, then any VNet.
    local default_interface
    default_interface=$(pvesh get /nodes/"$(hostname -f)"/network --output-format json | jq -r '[.[] | select(.type == "bridge") | .iface] | if any(. == "vmbr0") then "vmbr0" else .[0] end')
    
    if [[ -z "$default_interface" || "$default_interface" == "null" ]]; then
        default_interface=$(pvesh get /cluster/sdn/vnets --output-format json | jq -r '.[0].vnet' 2>/dev/null)
    fi

    if [[ -z "$default_interface" || "$default_interface" == "null" ]]; then
        log_error "Could not auto-detect a network interface (Bridge or VNet)." && exit 1
    fi
    echo "$default_interface"
}

# --- UA: Функція для отримання шляху до сховища ---
# --- EN: Function to get storage path ---
get_storage_path() {
    local storage_id="$1"
    local path
    # UA: Витягуємо параметр 'path' з конфігураційного файлу Proxmox.
    # EN: Extract the 'path' parameter from the Proxmox configuration file.
    path=$(sed -n "/: ${storage_id}$/,/^[a-z]*: / { /path /p; }" /etc/pve/storage.cfg | awk '{print $2}')
    if [[ -z "$path" ]]; then
        echo ""
    else
        echo "$path"
    fi
}

# --- UA: Фіналізація налаштувань ---
# --- EN: Fill missing settings ---
finalize_settings() {
    # UA: Інтерактивні запити для всіх основних параметрів ВМ.
    # EN: Interactive prompts for all main VM parameters.
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        if ! command -v whiptail &> /dev/null; then log_error "'whiptail' is required for interactive mode." && exit 1; fi
        local backtitle_text="Proxmox Ubuntu Template Creator"
        
        if [[ -z "$UBUNTU_CODENAME" ]]; then
            UBUNTU_CODENAME=$(whiptail --backtitle "$backtitle_text" --inputbox "Enter Ubuntu codename (e.g., noble, jammy)" 10 60 "$DEFAULT_UBUNTU_CODENAME" --title "Ubuntu Codename" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$VM_USER" ]]; then
            VM_USER=$(whiptail --backtitle "$backtitle_text" --inputbox "Enter the admin username to create" 10 60 "$DEFAULT_USER" --title "Admin Username" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$SSH_PUB_KEY_FILE" ]]; then
            SSH_PUB_KEY_FILE=$(whiptail --backtitle "$backtitle_text" --inputbox "Enter the path to your public SSH key" 10 60 "$DEFAULT_SSH_PUB_KEY_FILE" --title "SSH Public Key" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$TEMP_VM_ID" ]]; then
            TEMP_VM_ID=$(whiptail --backtitle "$backtitle_text" --inputbox "Set Temporary Virtual Machine ID" 10 60 "$(get_valid_nextid "$DEFAULT_VMID_PREFIX")" --title "Temporary VM ID" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$FINAL_TEMPLATE_NAME" ]]; then
            FINAL_TEMPLATE_NAME=$(whiptail --backtitle "$backtitle_text" --inputbox "Set the final template name" 10 60 "${DEFAULT_TEMPLATE_NAME_PREFIX}-${UBUNTU_CODENAME}" --title "Template Name" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$VM_CORES" ]]; then
            VM_CORES=$(whiptail --backtitle "$backtitle_text" --inputbox "Allocate CPU Cores" 10 60 "$DEFAULT_VM_CORES" --title "CPU Cores" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$VM_MEMORY" ]]; then
            VM_MEMORY=$(whiptail --backtitle "$backtitle_text" --inputbox "Allocate RAM in MB" 10 60 "$DEFAULT_VM_MEMORY" --title "RAM (MB)" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$VM_DISK_SIZE" ]]; then
            VM_DISK_SIZE=$(whiptail --backtitle "$backtitle_text" --inputbox "Set disk size (e.g., 32G)" 10 60 "$DEFAULT_VM_DISK_SIZE" --title "Disk Size" 3>&1 1>&2 2>&3) || exit 1
        fi
        if [[ -z "$USER_TAGS" ]]; then
            USER_TAGS=$(whiptail --backtitle "$backtitle_text" --inputbox "Enter any additional comma-separated tags (e.g., web,24.04)" 10 60 "" --title "Custom Tags" 3>&1 1>&2 2>&3) || exit 1
        fi
    fi

    # --- UA: Встановлення значень за замовчуванням, якщо вони не були надані ---
    # --- EN: Set default values if they were not provided ---
    if [[ -z "$VM_USER" ]]; then VM_USER="$DEFAULT_USER"; fi
    if [[ -z "$UBUNTU_CODENAME" ]]; then UBUNTU_CODENAME="$DEFAULT_UBUNTU_CODENAME"; fi
    if [[ -z "$SSH_PUB_KEY_FILE" ]]; then SSH_PUB_KEY_FILE="$DEFAULT_SSH_PUB_KEY_FILE"; fi
    if [[ -z "$TEMP_VM_ID" ]]; then TEMP_VM_ID=$(get_valid_nextid "$DEFAULT_VMID_PREFIX"); fi
    if [[ -z "$FINAL_TEMPLATE_NAME" ]]; then FINAL_TEMPLATE_NAME="${DEFAULT_TEMPLATE_NAME_PREFIX}-${UBUNTU_CODENAME}"; fi
    if [[ -z "$VM_CORES" ]]; then VM_CORES="$DEFAULT_VM_CORES"; fi
    if [[ -z "$VM_MEMORY" ]]; then VM_MEMORY="$DEFAULT_VM_MEMORY"; fi
    if [[ -z "$VM_DISK_SIZE" ]]; then VM_DISK_SIZE="$DEFAULT_VM_DISK_SIZE"; fi
    if [[ ! -f "$SSH_PUB_KEY_FILE" ]]; then log_error "SSH key file not found: ${SSH_PUB_KEY_FILE}"; exit 1; fi
}

# --- UA: Функція "розумного" вибору/завантаження образу ---
# --- EN: "Smart" image source resolution function ---
resolve_image_source() {
    log_info "Resolving image source for '${UBUNTU_CODENAME}'..."
    local image_base_name="${UBUNTU_CODENAME}-server-cloudimg-${DEFAULT_UBUNTU_ARCH}"
    local image_url="${DEFAULT_IMAGE_BASE_URL}/${UBUNTU_CODENAME}/current/${image_base_name}.img"
    
    # UA: Отримуємо дату модифікації образу на сервері.
    # EN: Get the image modification date from the server.
    local latest_remote_mtime=""
    local remote_last_mod_str
    remote_last_mod_str=$(curl -sI "$image_url" | grep -i '^Last-Modified:' | sed 's/Last-Modified: //i' | tr -d '\r')
    if [[ -n "$remote_last_mod_str" ]]; then
        latest_remote_mtime=$(date -d "$remote_last_mod_str" +%s)
    else
        log_warn "Could not retrieve modification date from server. Online check is disabled."
    fi

    # UA: Обробка прапорця примусового завантаження.
    # EN: Handle the force download flag.
    if [[ "$FORCE_DOWNLOAD" == "true" ]]; then
        if [[ -z "$latest_remote_mtime" ]]; then log_error "Cannot force download without a connection to the server." && exit 1; fi
        log_info "Force download flag is set. Downloading latest version..."
        download_and_verify "$image_url" "${image_base_name}-${latest_remote_mtime}.img"
        return
    fi

    # UA: Шукаємо всі локальні версії образу.
    # EN: Find all local versions of the image.
    local local_images=()
    while IFS= read -r line; do local_images+=("$line"); done < <(find "${DOWNLOAD_DIR}" -maxdepth 1 -name "${image_base_name}-*.img" 2>/dev/null | sort -rV)

    # UA: Інтерактивний вибір джерела образу.
    # EN: Interactive image source selection.
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        local menu_options=()
        local lookup_array=()
        local index=1
        local header
        header=$(printf "%-32s | %-15s | %s" "IMAGE" "SOURCE" "DATE")
        
        if [[ -n "$latest_remote_mtime" ]]; then
            local dl_text
            dl_text=$(printf "%-32s | %-15s | %s" "${image_base_name}" "HTTP" "$(date -d "@$latest_remote_mtime" '+%Y-%m-%d %H:%M')")
            menu_options+=("$index" "$dl_text")
            lookup_array+=("DOWNLOAD")
            index=$((index+1))
        fi
        
        for img_path in "${local_images[@]}"; do
            local filename timestamp human_date item_text base_name_only
            filename=$(basename "$img_path")
            timestamp=$(echo "$filename" | sed -n "s/.*-\([0-9]\{10\}\)\.img/\1/p")
            human_date=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M')
            base_name_only=$(echo "$filename" | sed "s/-[0-9]\{10\}\.img//")
            item_text=$(printf "%-32s | %-15s | %s" "${base_name_only}" "${IMAGES_STORAGE}" "${human_date}")
            menu_options+=("$index" "$item_text")
            lookup_array+=("$img_path")
            index=$((index+1))
        done
        
        if [[ ${#lookup_array[@]} -eq 0 ]]; then
            if [[ -n "$latest_remote_mtime" ]]; then
                log_info "No local images found. Downloading..."
                download_and_verify "$image_url" "${image_base_name}-${latest_remote_mtime}.img"
                return
            else
                log_error "No local images found and cannot connect to the server." && exit 1
            fi
        fi
        
        local choice_index
        choice_index=$(whiptail --title "Image Source Selection" --menu "$header" 20 78 12 "${menu_options[@]}" 3>&1 1>&2 2>&3) || exit 1
        
        local actual_choice="${lookup_array[$((choice_index-1))]}"
        
        if [[ "$actual_choice" == "DOWNLOAD" ]]; then
            download_and_verify "$image_url" "${image_base_name}-${latest_remote_mtime}.img"
        elif [[ -n "$actual_choice" ]]; then
            LOCAL_IMAGE_PATH="$actual_choice"
        else
            log_error "Invalid selection. Aborting." && exit 1
        fi
        return
    fi

    # UA: Автоматична логіка: порівнюємо локальну версію з версією на сервері.
    # EN: Automatic logic: compare the local version with the server version.
    local latest_local_mtime=0
    if [[ ${#local_images[@]} -gt 0 ]]; then
        latest_local_mtime=$(basename "${local_images[0]}" | sed -n "s/.*-\([0-9]\{10\}\)\.img/\1/p")
    fi

    if [[ -n "$latest_remote_mtime" && "$latest_remote_mtime" -gt "$latest_local_mtime" ]]; then
        log_info "A newer image version is available on the server."
        download_and_verify "$image_url" "${image_base_name}-${latest_remote_mtime}.img"
    elif [[ "$latest_local_mtime" -gt 0 ]]; then
        log_success "Local image is up-to-date. Using the latest available local version."
        LOCAL_IMAGE_PATH="${local_images[0]}"
    elif [[ -n "$latest_remote_mtime" ]]; then
        log_info "No local images found. Downloading the latest version from the server."
        download_and_verify "$image_url" "${image_base_name}-${latest_remote_mtime}.img"
    else
        log_error "No local images found and cannot connect to the server. Please provide an image manually."
        exit 1
    fi
}

# --- UA: Функція для завантаження та перевірки ---
# --- EN: Download and verify function ---
download_and_verify() {
    local url="$1"
    local versioned_filename="$2"
    LOCAL_IMAGE_PATH="${DOWNLOAD_DIR}/${versioned_filename}"

    if [ -f "$LOCAL_IMAGE_PATH" ]; then
        log_warn "File ${versioned_filename} already exists. It will be overwritten."
    fi

    log_info "Downloading image to ${LOCAL_IMAGE_PATH}..."
    wget --progress=bar:force --tries=3 --timeout=180 -O "$LOCAL_IMAGE_PATH.partial" "$url"
    mv "$LOCAL_IMAGE_PATH.partial" "$LOCAL_IMAGE_PATH"
    
    log_success "Image downloaded successfully."
}

# --- UA: Функція створення тимчасової ВМ ---
# --- EN: Function to create the temporary VM ---
create_temp_vm() {
    qm create "${TEMP_VM_ID}" \
        --name "temp-template-build" --ostype l26 \
        --cores "${VM_CORES}" --memory "${VM_MEMORY}" \
        --net0 virtio,bridge="${VM_BRIDGE}" \
        --machine q35 --bios ovmf --scsihw virtio-scsi-pci --agent enabled=1
    qm set "${TEMP_VM_ID}" --efidisk0 "${DISK_STORAGE}:0,efitype=4m,pre-enrolled-keys=1"
}

# --- UA: Функція імпорту диска з надійною зміною розміру ---
# --- EN: Disk import function with robust resize ---
import_and_configure_disk() {
    log_info "Importing disk image as qcow2 from ${LOCAL_IMAGE_PATH}..."
    qm importdisk "${TEMP_VM_ID}" "${LOCAL_IMAGE_PATH}" "${DISK_STORAGE}" --format qcow2
    
    local full_volume_id
    full_volume_id=$(pvesh get /nodes/"${PROXMOX_NODE:-$(hostname -f)}"/qemu/"${TEMP_VM_ID}"/config --output-format json | jq -r '.unused0 | select(type == "string")')
    
    if [[ -z "$full_volume_id" || "$full_volume_id" == "null" ]]; then
        log_error "Could not parse the full volume ID for the imported disk." && exit 1
    fi

    local disk_path
    disk_path=$(pvesm path "$full_volume_id")

    log_info "Resizing disk image directly via qemu-img at ${disk_path}..."
    if qemu-img resize "${disk_path}" "${VM_DISK_SIZE}"; then
        log_success "qemu-img resize successful."
    else
        log_error "qemu-img resize failed." && exit 1
    fi
    
    log_info "Attaching imported disk (${full_volume_id}) as scsi0..."
    if qm set "${TEMP_VM_ID}" --scsi0 "${full_volume_id}"; then
        log_success "Disk attached successfully."
    else
        log_error "Failed to attach disk." && exit 1
    fi

    log_info "Rescanning disks for VM to update size in config..."
    if qm rescan --vmid "${TEMP_VM_ID}"; then
        log_success "Disks rescanned successfully."
    else
        log_warn "qm rescan failed. The disk size in Proxmox config might be incorrect. Attempting qm resize as a fallback..."
        if ! qm resize "${TEMP_VM_ID}" scsi0 "${VM_DISK_SIZE}"; then
            log_error "Fallback 'qm resize' also failed. Disk size in config is likely incorrect."
        fi
    fi

    qm set "${TEMP_VM_ID}" --boot order=scsi0 --ide2 "${DISK_STORAGE}:cloudinit"
    qm set "${TEMP_VM_ID}" --serial0 socket --vga serial0
}

# --- UA: Фінальна функція для автоматичного налаштування ВМ ---
# --- EN: Final function for automated VM setup ---
automate_vm_setup_with_userdata() {
    # ... (код функції без змін)
}

# --- UA: Функція перетворення на шаблон ---
# --- EN: Convert to template function ---
convert_vm_to_template() {
    log_info "Setting final versioned name, notes and tags..."
    
    local image_timestamp
    image_timestamp=$(basename "${LOCAL_IMAGE_PATH}" | sed -n "s/.*-\([0-9]\{10\}\)\.img/\1/p")
    
    local final_versioned_name="${FINAL_TEMPLATE_NAME}-${image_timestamp}"
    local notes="Created on $(date '+%Y-%m-%d %H:%M') from image $(basename "${LOCAL_IMAGE_PATH}")"
    
    local final_tags="$DEFAULT_BASE_TAGS"
    if [[ -n "$USER_TAGS" ]]; then
        final_tags="${final_tags},${USER_TAGS}"
    fi
    final_tags=$(echo "$final_tags" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    qm set "${TEMP_VM_ID}" --name "${final_versioned_name}" --description "${notes}" --tags "${final_tags}"
    
    log_info "Converting VM to template '${final_versioned_name}'..."
    qm template "${TEMP_VM_ID}"
}

# --- Головна функція ---
main() {
    log_info "--- Starting Ubuntu Cloud-Init Template Creation ---"
    
    log_info "### Step 1: Initialization & Configuration ###"
    parse_arguments "$@"
    
    DISK_STORAGE=$(select_storage "images" "VM Disks" "${DISK_STORAGE}")
    SNIPPETS_STORAGE=$(select_storage "snippets" "Cloud-Init Snippets" "${SNIPPETS_STORAGE:-$DISK_STORAGE}")
    IMAGES_STORAGE=$(select_storage "iso" "Cloud Images" "${IMAGES_STORAGE:-}")
    DOWNLOAD_DIR="$(get_storage_path "$IMAGES_STORAGE")/template/iso"
    VM_BRIDGE=$(select_network_interface "${VM_BRIDGE:-}")

    finalize_settings
    log_success "Configuration loaded."
    
    local disk_storage_path snippets_storage_path
    disk_storage_path=$(get_storage_path "$DISK_STORAGE")
    snippets_storage_path=$(get_storage_path "$SNIPPETS_STORAGE")
    
    log_info "-----------------------------------------------------"
    log_info "Execution Summary:"
    log_info "  - Admin User:           ${VM_USER}"
    log_info "  - SSH Key File:         ${SSH_PUB_KEY_FILE}"
    log_info "  - Temporary VM ID:        ${TEMP_VM_ID}"
    log_info "  - Base Template Name:   ${FINAL_TEMPLATE_NAME}"
    log_info "  - Custom Tags:          ${USER_TAGS:- (none)}"
    log_info "  - VM Disk Storage:      ${DISK_STORAGE} (Path: ${disk_storage_path:-N/A for block storage})"
    log_info "  - Snippets Storage:     ${SNIPPETS_STORAGE} (Path: ${snippets_storage_path})"
    log_info "  - Cloud Images Storage: ${IMAGES_STORAGE} (Path: ${DOWNLOAD_DIR})"
    log_info "  - VM Resources:           ${VM_CORES} Cores, ${VM_MEMORY}MB RAM, ${VM_DISK_SIZE} Disk"
    log_info "  - Network Interface:    ${VM_BRIDGE}"
    log_info "-----------------------------------------------------"
    
    log_info "### Step 2: Resolving Image Source ###"
    resolve_image_source
    log_success "Using image: ${LOCAL_IMAGE_PATH}"
    
    log_info "### Step 3: Temporary VM Creation ###"
    create_temp_vm
    log_success "Temporary VM ${TEMP_VM_ID} created."

    log_info "### Step 4: Disk Import & Configuration ###"
    import_and_configure_disk
    log_success "Disk imported and configured."

    log_info "### Step 5: Cloud-Init Provisioning & Cleanup ###"
    automate_vm_setup_with_userdata
    log_success "VM provisioned and artifacts cleaned successfully."

    log_info "### Step 6: Convert to Template ###"
    convert_vm_to_template
    
    local final_name
    final_name=$(pvesh get /cluster/resources --type vm --output-format json | jq -r ".[] | select(.vmid == ${TEMP_VM_ID}) | .name")
    log_success "Template '${final_name}' created."
    
    log_info "----------------------------------------------------"
    log_success "Script finished successfully!"
    log_info "Template '${final_name}' is ready to use on storage '${DISK_STORAGE}'."
    log_info "----------------------------------------------------"
}

main "$@"
exit 0
