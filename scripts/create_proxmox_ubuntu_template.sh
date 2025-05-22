#!/usr/bin/env bash

# UA: Скрипт для автоматизації створення шаблону Ubuntu cloud-init для Proxmox VE.
# EN: Script to automate the creation of an Ubuntu cloud-init template for Proxmox VE.

# UA: Зупиняти скрипт при першій помилці
# EN: Stop script on first error
set -e
# UA: Вважати помилкою використання неініціалізованих змінних
# EN: Treat unset variables as an error
set -u
# UA: Вважати помилкою, якщо будь-яка команда в конвеєрі (pipe) завершується з помилкою
# EN: Treat any command in a pipeline failing as an error
set -o pipefail

# --- UA: Кольори та атрибути для виводу (використовуємо tput для кращої сумісності) ---
# --- EN: Colors and attributes for output (using tput for better compatibility) ---
C_RESET=$(tput sgr0 2>/dev/null || echo '\033[0m')
C_RED=$(tput setaf 1 2>/dev/null || echo '\033[0;31m')
C_GREEN=$(tput setaf 2 2>/dev/null || echo '\033[0;32m')
C_YELLOW=$(tput setaf 3 2>/dev/null || echo '\033[0;33m')
C_BLUE=$(tput setaf 4 2>/dev/null || echo '\033[0;34m')
C_BOLD=$(tput bold 2>/dev/null || echo '\033[1m')

# --- UA: Функції для логування ---
# --- EN: Logging functions ---
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; }

# --- UA: Значення за замовчуванням ---
# --- EN: Default values ---
DEFAULT_UBUNTU_CODENAME="noble"
DEFAULT_UBUNTU_ARCH="amd64"
DEFAULT_IMAGE_BASE_URL="https://cloud-images.ubuntu.com"
DEFAULT_DOWNLOAD_DIR="/var/lib/vz/template/iso" # UA: Використовується, якщо не вдалося знайти кращий варіант
DEFAULT_PROXMOX_STORAGE="local-lvm" # UA: Типове сховище для дисків ВМ
DEFAULT_VMID_PREFIX="90"
DEFAULT_TEMPLATE_NAME_PREFIX="ubuntu"
DEFAULT_VM_CORES="2"
DEFAULT_VM_MEMORY="2048" # MB
DEFAULT_VM_DISK_SIZE="32G"
DEFAULT_VM_BRIDGE="vmbr0"
DEFAULT_PROXMOX_NODE=""
DEFAULT_SSH_PUB_KEY_FILE="$HOME/.ssh/id_ed25519.pub"
DEFAULT_BASE_TAGS="cloudinit,automated-template"
DEFAULT_GIT_REPO_URL="https://github.com/os4-dev/infra-commons" # UA: Встановлено фіксований URL
DEFAULT_SCRIPT_LANG="en"
DEFAULT_SCRIPT_MARKER="Created-by: create_proxmox_ubuntu_template.sh (infra-commons)" # UA: Маркер для нотаток ВМ

# --- UA: Робочі змінні (будуть ініціалізовані пізніше) ---
# --- EN: Working variables (will be initialized later) ---
UBUNTU_CODENAME=""
UBUNTU_ARCH=""
IMAGE_BASE_URL=""
DOWNLOAD_DIR=""
IMAGE_PATH_SEGMENT=""
IMAGE_FILENAME_PATTERN=""
IMAGE_URL=""
LOCAL_IMAGE_PATH=""
VMID_PREFIX=""
TEMPLATE_NAME_PREFIX=""
VM_CORES=""
VM_MEMORY=""
VM_DISK_SIZE=""
VM_BRIDGE=""
PROXMOX_STORAGE_ACTUAL=""
PROXMOX_NODE=""
SSH_PUB_KEY_FILE=""
BASE_TAGS=""
ADDITIONAL_TAGS=""
TEMP_VM_ID=""
FINAL_TEMPLATE_NAME=""
PROXMOX_STORAGE_USER_SPECIFIED=""
DOWNLOAD_DIR_USER_SPECIFIED=""
SCRIPT_LANG=""
SCRIPT_MARKER=""
GIT_REPO_URL=""
FLAG_AUTO_SETUP="false"
FLAG_FORCE_CLEANUP_VM="false"
FLAG_KEEP_IMAGE="false"

# --- UA: Функція для виведення довідки ---
# --- EN: Function to display help message ---
show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "This script automates the creation of an Ubuntu cloud-init template for Proxmox VE."
    echo "The template will be marked as originating from '${DEFAULT_GIT_REPO_URL}'."
    echo ""
    echo "Options:"
    echo "  -h, --help                  Show this help message and exit."
    echo "  -c, --codename CODENAME     Ubuntu version codename (REQUIRED). Examples: noble, jammy, focal."
    echo "  -a, --arch ARCH             Architecture (default: ${DEFAULT_UBUNTU_ARCH}). Example: amd64, arm64."
    echo "  -s, --storage STORAGE_ID    Proxmox storage ID for the VM disk/template."
    echo "                              (default: attempts to use detected ISO storage if suitable, fallback: ${DEFAULT_PROXMOX_STORAGE})."
    echo "  -n, --node NODE_NAME        Proxmox node name (if not specified, tries to use the current hostname)."
    echo "  -i, --vmid ID               VM ID to use for the temporary VM (default: auto-generated)."
    echo "  -t, --template-name NAME    Name for the final Proxmox template (default: ${DEFAULT_TEMPLATE_NAME_PREFIX}-<codename>-cloudinit)."
    echo "  --cores CORES               Number of CPU cores for the VM (default: ${DEFAULT_VM_CORES})."
    echo "  --memory MEMORY_MB          RAM for the VM in MB (default: ${DEFAULT_VM_MEMORY})."
    echo "  --disk-size DISK_SIZE_G     Disk size for the VM's main disk, e.g., 32G (default: ${DEFAULT_VM_DISK_SIZE%G}G)."
    echo "  --bridge BRIDGE             Network bridge for the VM (default: ${DEFAULT_VM_BRIDGE})."
    echo "  --ssh-key-file FILE_PATH    Path to SSH public key file (default: ${DEFAULT_SSH_PUB_KEY_FILE}). (Used only if automating SSH key injection - currently not implemented)."
    echo "  --image-base-url URL        Base URL for cloud images (default: ${DEFAULT_IMAGE_BASE_URL})."
    echo "  --download-dir DIR          Directory to download cloud images to."
    echo "                              (default: attempts to find a Proxmox storage for ISOs, fallback: ${DEFAULT_DOWNLOAD_DIR})."
    echo "  --add-tags TAGS             Comma-separated list of additional tags to add to the final template."
    echo "                              (Default tags added automatically: ${DEFAULT_BASE_TAGS},<codename>)"
    echo "  --auto-vm-setup           Attempt to fully automate VM setup using cloud-init user-data."
    echo "  --force-cleanup-vm        If a VM (NOT a template) with the target temporary VM ID exists AND has the script marker in notes, delete it before creating the new one. USE WITH CAUTION!"
    echo "  --keep-image              Do not prompt to delete the downloaded cloud image file after completion."
    echo "  --lang LANG_CODE          Language for script messages ('en' or 'uk', default: ${DEFAULT_SCRIPT_LANG})."
    echo ""
    echo "Example:"
    echo "  $(basename "$0") --codename jammy --template-name ubuntu-2204-ci --storage local-zfs"
    echo ""
    echo "Supported Ubuntu Codenames (examples for amd64 architecture):"
    echo "  noble (24.04 LTS), jammy (22.04 LTS), focal (20.04 LTS)"
    echo "  (Ensure the image exists at <IMAGE_BASE_URL>/<IMAGE_PATH_SEGMENT>/<IMAGE_FILENAME>)"
}

# --- UA: Функція для отримання інформації про сховище ISO (ID та шлях) ---
# --- EN: Function to get ISO storage info (ID and path) ---
get_iso_storage_info() {
    # EN: This function should now only output the "ID:PATH" string or empty string.
    # EN: Logging about its actions will be handled by the caller.
    if ! command -v pvesh &> /dev/null || ! command -v jq &> /dev/null; then
        # UA: Важливо вивести це попередження в stderr, щоб не потрапило в результат
        # EN: Important to output this warning to stderr to not be captured
        log_warn "'pvesh' or 'jq' command not found. Cannot auto-detect ISO storage." >&2
        echo "" && return
    fi
    local storage_info
    storage_info=$(pvesh get /storage --output-format json 2>/dev/null | \
               jq -r '.[] | select(.disable == null and .type == "dir" and (.content | contains("iso"))) | "\(.storage):\(.path)"' | \
               head -n 1) # Select active storages only (implicit by .disable == null)

    if [ -n "$storage_info" ]; then
        echo "$storage_info" # Повертаємо "ID:PATH"
    else
        # UA: Це попередження також краще в stderr, якщо ми не хочемо його бачити в логах вищого рівня
        # EN: This warning also better to stderr if we don't want it in higher level logs
        log_warn "No suitable 'dir' type storage with 'iso' content type found via pvesh." >&2
        echo "" # Повертаємо порожній рядок
    fi
}

# --- UA: Функція для перевірки, чи сховище підтримує певний тип контенту ---
# --- EN: Function to check if a storage supports a specific content type ---


check_storage_content_type() {
    local storage_id="$1"
    local content_type_to_check="$2"

    if ! command -v pvesh &> /dev/null || ! command -v jq &> /dev/null; then
        log_warn "'pvesh' or 'jq' not available for storage content check." && return 1
    fi

    # Отримуємо інформацію про конкретне сховище
    # Get information about the specific storage
    local storage_json
    storage_json=$(pvesh get /storage/"${storage_id}" --output-format json 2>/dev/null)

    if [ -z "$storage_json" ]; then
        log_warn "Could not retrieve information for storage '${storage_id}'." && return 1
    fi

    # Перевіряємо, що сховище активне (поле "disable" відсутнє або не 1) 
    # Check that the storage is active (the "disable" field is absent or its value is not 1)
    # та підтримує вказаний тип контенту.
    # and supports the specified content type.
    if echo "$storage_json" | jq -e "(.disable == null or .disable != 1) and (.content | contains(\"${content_type_to_check}\"))" > /dev/null; then
        log_info "Active storage '${storage_id}' supports '${content_type_to_check}' content type." && return 0
    else
        log_info "Storage '${storage_id}' is inactive or does NOT support '${content_type_to_check}' content type." && return 1
    fi
}


# --- UA: Функція для встановлення деталей образу на основі кодової назви ---
# --- EN: Function to set image details based on codename ---
set_ubuntu_image_details() {
    local selected_codename="$1"
    local selected_arch="$2"
    log_info "Setting image details for Ubuntu ${selected_codename} (${selected_arch})..."
    case "${selected_codename}" in
        noble|jammy|focal) # Add more supported versions here
            IMAGE_PATH_SEGMENT="${selected_codename}/current"
            IMAGE_FILENAME_PATTERN="${selected_codename}-server-cloudimg-${selected_arch}.img"
            ;;
        *) log_error "Unsupported Ubuntu codename: '${selected_codename}'."; show_help; exit 1 ;;
    esac
    if [ -z "$IMAGE_PATH_SEGMENT" ] || [ -z "$IMAGE_FILENAME_PATTERN" ]; then
        log_error "Internal error: Failed to determine image path or filename pattern for ${selected_codename}." && exit 1
    fi
    IMAGE_FILENAME=$(echo "$IMAGE_FILENAME_PATTERN" | sed "s/{{codename}}/${selected_codename}/g; s/{{arch}}/${selected_arch}/g")
    log_success "Image details set: Path segment '${IMAGE_PATH_SEGMENT}', Filename '${IMAGE_FILENAME}'"
}

# --- UA: Функція для створення тимчасової ВМ з EFI диском (з опцією очищення та перевіркою маркера) ---
# --- EN: Function to create the temporary VM with EFI disk (with cleanup option and marker check) ---
create_temp_vm() {
    log_info "Step 2: Checking for existing VM/Template with ID ${TEMP_VM_ID} on node ${PROXMOX_NODE}..." # Можна залишити логування вузла для інформації
    local vm_exists="false"
    local is_template="false"
    local existing_desc=""

    if qm status "${TEMP_VM_ID}" > /dev/null 2>&1; then
        vm_exists="true"
        local config_output
        config_output=$(qm config "${TEMP_VM_ID}" --current 2>/dev/null || echo "")
        if echo "$config_output" | grep -q '^[[:space:]]*template:[[:space:]]*1'; then
            is_template="true"
        else
            existing_desc=$(echo "$config_output" | grep '^description:' | sed 's/^description:[[:space:]]*//' || echo "")
        fi
    fi

    if [ "$vm_exists" == "true" ]; then
        if [ "$is_template" == "true" ]; then
            log_error "A template (ID: ${TEMP_VM_ID}) already exists on node ${PROXMOX_NODE}. Cannot proceed."
            exit 1
        else # It's an existing VM
            log_warn "Existing VM (ID: ${TEMP_VM_ID}) found on node ${PROXMOX_NODE}."
            if [ "$FLAG_FORCE_CLEANUP_VM" == "true" ]; then
                log_info "Flag --force-cleanup-vm is set. Checking VM description for script marker..."
                if echo "${existing_desc}" | grep -q -F "${SCRIPT_MARKER}"; then
                    log_warn "Marker '${SCRIPT_MARKER}' found in description. Proceeding with automatic cleanup."
                    log_warn "Attempting to stop and destroy the existing VM ${TEMP_VM_ID} on node ${PROXMOX_NODE}..."
                    qm stop "${TEMP_VM_ID}" --timeout 60 || log_warn "Could not stop VM ${TEMP_VM_ID}. Continuing with destroy."
                    if qm destroy "${TEMP_VM_ID}" --purge --destroy-unreferenced-disks 1; then
                        log_success "Existing VM ${TEMP_VM_ID} destroyed successfully."
                    else
                        log_error "Failed to destroy existing VM ${TEMP_VM_ID}. Please check manually."
                        exit 1
                    fi
                else # Marker not found
                    log_error "Script marker not found in the description of existing VM ${TEMP_VM_ID}."
                    # ... (решта повідомлень про помилку)
                    exit 1
                fi
            else # Cleanup flag not set
                log_error "VM with ID ${TEMP_VM_ID} already exists on node ${PROXMOX_NODE}."
                # ... (решта повідомлень про помилку)
                exit 1
            fi
        fi
    fi

    # --- UA: Створення нової ВМ ---
    # --- EN: Create the new VM ---
    log_info "Proceeding to create temporary VM (ID: ${TEMP_VM_ID}) on current node (expected: ${PROXMOX_NODE})..."
    log_info "Executing: qm create ${TEMP_VM_ID} --name temp-${FINAL_TEMPLATE_NAME} ..."
    if qm create "${TEMP_VM_ID}" \
        --name "temp-${FINAL_TEMPLATE_NAME}" --ostype l26 \
        --cores "${VM_CORES}" --memory "${VM_MEMORY}" --net0 virtio,bridge="${VM_BRIDGE}" \
        --machine q35 --bios ovmf --scsihw virtio-scsi-pci --agent enabled=1; then
        log_success "Temporary VM ${TEMP_VM_ID} created successfully."
    else
        log_error "Failed to create temporary VM ${TEMP_VM_ID}." && exit 1
    fi

    # --- UA: Додавання маркера скрипту в нотатки ВМ ---
    # --- EN: Add script marker to VM notes ---

    local vm_creation_notes
    vm_creation_notes=$(printf "%s\nIntended-template: %s\nTimestamp: %s" \
                        "${SCRIPT_MARKER}" \
                        "${FINAL_TEMPLATE_NAME}" \
                        "$(date '+%Y-%m-%d %H:%M:%S %Z')")
    log_info "Adding creation notes to VM ${TEMP_VM_ID}..."
    if qm set "${TEMP_VM_ID}" --description "${vm_creation_notes}"; then
        log_success "Creation notes added successfully."
    else
        log_warn "Failed to add creation notes to VM ${TEMP_VM_ID}." # Non-fatal
    fi

    # --- UA: Додавання EFI диска ---
    # --- EN: Add EFI disk ---
    log_info "Sitep 2.1: Adding EFI disk to VM ${TEMP_VM_ID} on storage ${PROXMOX_STORAGE_ACTUAL}..."
    if qm set "${TEMP_VM_ID}" \
        --efidisk0 "${PROXMOX_STORAGE_ACTUAL}":0,efitype=4m,pre-enrolled-keys=1,format=raw; then 
        log_success "EFI disk added successfully to VM ${TEMP_VM_ID} on storage ${PROXMOX_STORAGE_ACTUAL}."
    else
        log_error "Failed to add EFI disk to VM ${TEMP_VM_ID}."
        log_info "Attempting to clean up partially created VM ${TEMP_VM_ID}..."
        qm destroy "${TEMP_VM_ID}" --purge --destroy-unreferenced-disks 1 || log_warn "Could not automatically destroy VM ${TEMP_VM_ID}."
        exit 1
    fi
    }

# --- UA: Функція для перевірки середовища та необхідних утиліт ---
# --- EN: Function to check environment and required utilities ---
check_environment() {
    log_info "Checking required utilities..."
    local missing_utils=0
    local utils_to_check=("wget" "qm" "tput" "grep" "sed" "awk" "cut" "head" "mktemp" "sha256sum") # Added common text utils
    if command -v pvesh &> /dev/null; then utils_to_check+=("jq" "pvesh"); fi

    for util in "${utils_to_check[@]}"; do
        if ! command -v "$util" &> /dev/null; then
            log_error "Required utility '$util' is not installed or not in PATH." && missing_utils=$((missing_utils + 1))
        fi
    done
    if [ "$missing_utils" -gt 0 ]; then
         log_error "Please install missing utilities (like coreutils, grep, sed, jq, wget) and try again." && exit 1
    fi
    log_success "All required base utilities are present."
    # Add check for qm permissions? Maybe check if user is root or in appropriate group?
}

# --- UA: Функція для перевірки існуючого шаблону ---
# --- EN: Function to check for existing template ---
check_existing_template() {
    local template_name_to_check="$1"
    log_info "Checking if a template named '${template_name_to_check}' already exists..."
    if ! command -v pvesh &> /dev/null || ! command -v jq &> /dev/null; then
        log_warn "'pvesh' or 'jq' not found. Cannot check for existing template." && return
    fi
    if pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
       jq -e --arg name "$template_name_to_check" '.[] | select(.template==1 and .name==$name)' > /dev/null; then
        log_error "A template named '${template_name_to_check}' already exists."
        log_error "Please remove it manually or choose a different name (--template-name)."
        exit 1
    else
        log_success "No existing template found with name '${template_name_to_check}'. Proceeding..."
    fi
}

# --- UA: Функція для завантаження образу та перевірки контрольної суми ---
# --- EN: Function to download the image and verify checksum ---
download_image() {
    log_info "Step 1: Handling cloud image download and verification..."
    log_info "  Image URL:  ${IMAGE_URL}"
    log_info "  Local Path: ${LOCAL_IMAGE_PATH}"

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        log_info "Download directory ${DOWNLOAD_DIR} does not exist. Attempting to create..."
        if mkdir -p "$DOWNLOAD_DIR"; then log_success "Download directory created: ${DOWNLOAD_DIR}";
        elif sudo mkdir -p "$DOWNLOAD_DIR"; then
             log_success "Download directory created with sudo: ${DOWNLOAD_DIR}"
             log_warn "Ensure the user running the script has write permissions to ${DOWNLOAD_DIR}"
        else log_error "Could not create download directory ${DOWNLOAD_DIR}." && exit 1; fi
    fi

    if [ ! -f "$LOCAL_IMAGE_PATH" ]; then
        log_info "Image not found locally. Downloading..."
        if wget --tries=3 --timeout=120 -O "$LOCAL_IMAGE_PATH.partial" "$IMAGE_URL"; then # Increased timeout
            mv "$LOCAL_IMAGE_PATH.partial" "$LOCAL_IMAGE_PATH"
            log_success "Image downloaded successfully to ${LOCAL_IMAGE_PATH}."
        else
            log_error "Failed to download image from ${IMAGE_URL}." && rm -f "$LOCAL_IMAGE_PATH.partial" && exit 1
        fi
    else
        log_success "Image already exists locally: ${LOCAL_IMAGE_PATH}"
    fi

    # --- UA: Перевірка контрольної суми ---
    # --- EN: Checksum verification ---
    local checksum_url="${IMAGE_BASE_URL}/${IMAGE_PATH_SEGMENT}/SHA256SUMS"
    local expected_checksum=""
    local local_checksum=""

    log_info "Attempting to verify SHA256 checksum for ${IMAGE_FILENAME}..."
    local checksum_file_content
    checksum_file_content=$(wget -qO- "${checksum_url}")

    if [ -z "$checksum_file_content" ]; then
        log_warn "Could not download checksum file from ${checksum_url}. Skipping verification."
        return 0
    fi

    expected_checksum=$(echo "$checksum_file_content" | grep "${IMAGE_FILENAME}" | awk '{print $1}')

    if [ -z "$expected_checksum" ]; then
        log_warn "Could not find checksum for ${IMAGE_FILENAME} in the downloaded SHA256SUMS file. Skipping verification."
        return 0
    fi

    log_info "Calculating local SHA256 checksum for ${LOCAL_IMAGE_PATH}..."
    local_checksum=$(sha256sum "${LOCAL_IMAGE_PATH}" | awk '{print $1}')

    log_info "Expected Checksum: ${expected_checksum}"
    log_info "Local Checksum:    ${local_checksum}"

    if [ "$local_checksum" == "$expected_checksum" ]; then
        log_success "Checksum verification passed for ${IMAGE_FILENAME}."
    else
        log_error "Checksum verification FAILED for ${IMAGE_FILENAME}!"
        log_error "The downloaded file might be corrupted."
        local confirm_delete_corrupted=""
        read -r -p "${C_YELLOW}Do you want to delete the potentially corrupted file (${LOCAL_IMAGE_PATH})? (y/N): ${C_RESET}" confirm_delete_corrupted
        if [[ "$confirm_delete_corrupted" =~ ^([yY][eE][sS]|[yY])$ ]]; then
             rm -f "${LOCAL_IMAGE_PATH}"
             log_info "Corrupted file removed."
        fi
        exit 1
    fi
}

# --- UA: Функція для імпорту диска ВМ ---
# --- EN: Function to import the VM disk ---
import_vm_disk() {
    log_info "Step 3: Importing disk from ${LOCAL_IMAGE_PATH} to VM ${TEMP_VM_ID} on storage ${PROXMOX_STORAGE_ACTUAL}..."
    if qm importdisk "${TEMP_VM_ID}" "${LOCAL_IMAGE_PATH}" "${PROXMOX_STORAGE_ACTUAL}"; then
        log_success "Disk imported successfully."
    else
        log_error "Failed to import disk ${LOCAL_IMAGE_PATH} to VM ${TEMP_VM_ID} on storage ${PROXMOX_STORAGE_ACTUAL}."
        exit 1
    fi
}

# --- UA: Функція для фінального налаштування ВМ ---
# --- EN: Function for final VM configuration ---
configure_vm_settings() {
    log_info "Step 4: Configuring VM ${TEMP_VM_ID} settings..."

    local full_volume_id_for_unused0
    local disk_config_line
    local disk_path_on_host # UA: Шлях до файлу образу на хості / EN: Path to the image file on the host

    log_info "Retrieving full volume ID for the imported disk (registered as unused0)..."
    if ! command -v pvesh &> /dev/null || ! command -v jq &> /dev/null; then
        log_warn "'pvesh' or 'jq' not found. Using 'qm config' as fallback for unused disk volume ID." >&2
        disk_config_line=$(qm config "${TEMP_VM_ID}" --current 2>/dev/null | grep '^unused0:')
        if [ -z "$disk_config_line" ]; then
            log_error "Could not find unused0 disk in VM ${TEMP_VM_ID} configuration after import via 'qm config'."
            exit 1
        fi
        full_volume_id_for_unused0=$(echo "$disk_config_line" | sed -e 's/^unused0:[[:space:]]*//' -e 's/,[^,]*$//')
    else
        full_volume_id_for_unused0=$(pvesh get /nodes/"${PROXMOX_NODE}"/qemu/"${TEMP_VM_ID}"/config --output-format json 2>/dev/null | jq -r '.unused0 | select(type == "string") | sub(",size=[0-9]+[KMGT]?"; "")' || echo "")
    fi

    if [ -z "$full_volume_id_for_unused0" ] || [ "$full_volume_id_for_unused0" == "null" ]; then
        log_error "Could not parse the full volume ID for unused0 for VM ${TEMP_VM_ID}."
        log_info "Current VM config dump:"
        qm config "${TEMP_VM_ID}" --current || true
        exit 1
    fi
    log_success "Successfully retrieved full volume ID for imported disk (unused0): ${full_volume_id_for_unused0}"

    # UA: Отримуємо шлях до файлу образу на хості зі сховища типу 'dir'
    # EN: Get the path to the image file on the host from 'dir' type storage
    local storage_id_from_volume
    local relative_path_from_volume
    storage_id_from_volume=$(echo "$full_volume_id_for_unused0" | cut -d':' -f1)
    relative_path_from_volume=$(echo "$full_volume_id_for_unused0" | cut -d':' -f2-)

    # UA: Отримуємо фізичний шлях до сховища
    # EN: Get the physical path of the storage
    # UA: Це припускає, що PROXMOX_STORAGE_ACTUAL - це ID, а не шлях
    # EN: This assumes PROXMOX_STORAGE_ACTUAL is an ID, not a path
    local storage_base_path
    storage_base_path=$(pvesh get /storage/"${PROXMOX_STORAGE_ACTUAL}" --output-format json 2>/dev/null | jq -r '.path // empty' || echo "")

    if [ -z "$storage_base_path" ]; then
        log_error "Could not determine base path for storage '${PROXMOX_STORAGE_ACTUAL}'. Cannot construct full disk path for qemu-img resize."
        exit 1
    fi
    disk_path_on_host="${storage_base_path}/images/${relative_path_from_volume}" # Proxmox stores VM images in an 'images' subdirectory for 'dir' storage

    log_info "Constructed disk path on host: ${disk_path_on_host}"

    # --- UA: Зміна розміру образу диска за допомогою qemu-img ---
    # --- EN: Resize disk image using qemu-img ---
    log_info "Resizing disk image ${disk_path_on_host} to ${VM_DISK_SIZE} using qemu-img..."
    if /usr/bin/qemu-img resize -f raw "${disk_path_on_host}" "${VM_DISK_SIZE}"; then
        log_success "Disk image resized successfully using qemu-img."
    else
        log_error "Failed to resize disk image using qemu-img for VM ${TEMP_VM_ID}."
        # UA: Можливо, не варто виходити, якщо qm rescan потім спрацює, але це ризиковано
        # EN: Might not exit if qm rescan works later, but it's risky
        exit 1
    fi

    # --- UA: Підключення імпортованого диска ---
    # --- EN: Attach the imported disk ---
    log_info "Attaching imported disk (${full_volume_id_for_unused0}) as scsi0..."
    if qm set "${TEMP_VM_ID}" --scsi0 "${full_volume_id_for_unused0}"; then
        log_success "Imported disk attached successfully as scsi0."
    else
        log_error "Failed to attach imported disk ${full_volume_id_for_unused0} as scsi0."
        exit 1
    fi

    # --- UA: Пересканування дисків ВМ, щоб Proxmox побачив новий розмір ---
    # --- EN: Rescan VM disks for Proxmox to see the new size ---
    log_info "Rescanning disks for VM ${TEMP_VM_ID} to update size in config..."
    if qm disk rescan --vmid "${TEMP_VM_ID}"; then
        log_success "Disks rescanned successfully for VM ${TEMP_VM_ID}."
        # UA: Затримка, щоб переконатися, що конфігурація оновилася перед наступними командами
        # EN: Delay to ensure config is updated before next commands
        sleep 3
        # UA: Перевіряємо, чи оновився розмір у конфігурації
        # EN: Verify if the size in config was updated
        local current_disk_size_in_config
        current_disk_size_in_config=$(qm config "${TEMP_VM_ID}" --current 2>/dev/null | grep "^scsi0:" | sed -e 's/.*,size=\([0-9]\+[KMGT]\+\).*/\1/' || echo "N/A")
        log_info "Disk scsi0 size in Proxmox config after rescan: ${current_disk_size_in_config}"
        if [[ "$current_disk_size_in_config" == *"${VM_DISK_SIZE}"* ]]; then
            log_success "Proxmox config updated with new disk size ${VM_DISK_SIZE}."
        else
            log_warn "Proxmox config might not reflect the new disk size ${VM_DISK_SIZE} immediately. Expected: ${VM_DISK_SIZE}, Got: ${current_disk_size_in_config}."
            log_warn "Attempting to use 'qm resize' as a fallback to ensure config update..."
            if qm resize "${TEMP_VM_ID}" scsi0 "${VM_DISK_SIZE}"; then
                log_success "Fallback 'qm resize' successful, config should be updated."
            else
                log_error "Fallback 'qm resize' also failed. Disk size in config might be incorrect."
            fi
        fi
    else
        log_error "Failed to rescan disks for VM ${TEMP_VM_ID}. The disk size in Proxmox config might be incorrect."
        log_warn "Attempting 'qm resize' as a fallback..."
        if qm resize "${TEMP_VM_ID}" scsi0 "${VM_DISK_SIZE}"; then
             log_success "Fallback 'qm resize' successful."
        else
             log_error "Fallback 'qm resize' also failed. Disk size in config is likely incorrect."
        fi
    fi


    # UA: Додаємо пристрій CloudInit (зазвичай як IDE)
    # EN: Add CloudInit drive (usually as IDE)
    log_info "Adding CloudInit drive..."
    if qm set "${TEMP_VM_ID}" --ide2 "${PROXMOX_STORAGE_ACTUAL}:cloudinit"; then
        log_success "CloudInit drive added successfully."
    else
        log_error "Failed to add CloudInit drive to VM ${TEMP_VM_ID}."
        exit 1
    fi

    # UA: Встановлюємо порядок завантаження, щоб ВМ завантажувалася з імпортованого диска
    # EN: Set the boot order to boot from the imported disk
    log_info "Setting boot order to scsi0..."
    if qm set "${TEMP_VM_ID}" --boot order=scsi0; then
        log_success "Boot order set successfully to scsi0."
    else
        log_error "Failed to set boot order for VM ${TEMP_VM_ID}."
        exit 1
    fi

    # UA: Налаштовуємо послідовну консоль (рекомендовано для cloud-init образів)
    # EN: Configure serial console (recommended for cloud-init images)
    log_info "Configuring serial console (serial0)..."
    if qm set "${TEMP_VM_ID}" --serial0 socket --vga serial0; then
        log_success "Serial console configured successfully."
    else
        log_warn "Failed to configure serial console for VM ${TEMP_VM_ID}."
    fi

    log_success "VM ${TEMP_VM_ID} configuration finished."
}

# --- UA: Функція для виведення інструкцій для ручного налаштування ВМ ---
# --- EN: Function to prompt the user for manual VM setup steps ---
prompt_for_manual_steps() {
    local motd_content
    motd_content=$(printf "\n#################################################################\n#%71s#\n#  This VM template was created using a script from:            #\n#  %-60s #\n#%71s#\n#  OS Version: Ubuntu %-46s #\n#  Template Name: %-51s #\n#  Creation Date: %-51s #\n#%71s#\n#################################################################\n" \
                    "" "${GIT_REPO_URL}" "" \
                    "${UBUNTU_CODENAME} (${UBUNTU_ARCH})" \
                    "${FINAL_TEMPLATE_NAME}" \
                    "$(date '+%Y-%m-%d %H:%M:%S %Z')" "")

    local motd_content_escaped=$(echo "$motd_content" | sed 's/\\/\\\\/g; s/`/\\`/g; s/\$/\\$/g; s/"/\\"/g')

    if [ "$SCRIPT_LANG" == "uk" ]; then
        # --- Українська версія ---
        echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
        echo -e "${C_YELLOW}Крок 5: ПОТРІБНЕ РУЧНЕ ВТРУЧАННЯ${C_RESET}"
        echo -e "${C_YELLOW}Наступні кроки необхідно виконати в консолі ВМ для завершення підготовки шаблону.${C_RESET}"
        echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
        echo -e "${C_BLUE}[INFO]${C_RESET} Необхідні дії:"
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 1. Запустіть тимчасову ВМ (ID: ${TEMP_VM_ID}) через веб-інтерфейс Proxmox VE або командою:"
        echo -e "   ${C_YELLOW}qm start ${TEMP_VM_ID}${C_RESET}"
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 2. Підключіться до консолі ВМ ('Serial Console 0'). Дочекайтеся повного завантаження системи."
        echo -e "${C_BLUE}[INFO]${C_RESET}    Cloud-init може потребувати часу."
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 3. Після входу в систему виконайте наступні команди всередині ВМ:"
        echo ""
        echo -e "   ${C_BLUE}# UA: Встановлення/Оновлення QEMU Guest Agent${C_RESET}"
        echo -e "   ${C_YELLOW}sudo apt update && sudo apt install -y qemu-guest-agent${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Запуск та увімкнення сервісу агента${C_RESET}"
        echo -e "   ${C_YELLOW}sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Оновлення системи та очищення${C_RESET}"
        echo -e "   ${C_YELLOW}sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean${C_RESET}"
        echo -e "   ${C_BLUE}# UA: (Опціонально) Налаштування консолі (шрифт, розкладка) - ІНТЕРАКТИВНО${C_RESET}"
        echo -e "   ${C_YELLOW}sudo dpkg-reconfigure console-setup${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Видалення ключів хоста SSH${C_RESET}"
        echo -e "   ${C_YELLOW}sudo rm -f /etc/ssh/ssh_host_*${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Очищення machine-id${C_RESET}"
        echo -e "   ${C_YELLOW}sudo truncate -s 0 /etc/machine-id${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Відновлення посилання machine-id${C_RESET}"
        echo -e "   ${C_YELLOW}sudo ln -sf /var/lib/dbus/machine-id /etc/machine-id${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Очищення cloud-init${C_RESET}"
        echo -e "   ${C_YELLOW}sudo cloud-init clean --logs --seed${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Створення файлу /etc/motd з інформацією про шаблон${C_RESET}"
        echo -e "   ${C_YELLOW}echo \"${motd_content_escaped}\" | sudo tee /etc/motd${C_RESET}"
        echo -e "   ${C_BLUE}# UA: Очищення історії команд${C_RESET}"
        echo -e "   ${C_YELLOW}history -c && history -w && sudo history -c && sudo history -w${C_RESET}"
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 4. Після успішного виконання всіх команд, вимкніть ВМ зсередини:"
        echo -e "   ${C_YELLOW}sudo poweroff${C_RESET}"
        echo ""
        echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
        echo -e "${C_BOLD}UA: Натисніть клавішу [Enter] ПІСЛЯ повного вимкнення ВМ, щоб продовжити...${C_RESET}"
        read -r -p ""
    else
        # --- English version (default) ---
        echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
        echo -e "${C_YELLOW}Step 5: MANUAL INTERVENTION REQUIRED${C_RESET}"
        echo -e "${C_YELLOW}The next steps must be performed inside the VM console to finalize the template.${C_RESET}"
        echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
        echo -e "${C_BLUE}[INFO]${C_RESET} Action Required:"
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 1. Start the temporary VM (ID: ${TEMP_VM_ID}) using the Proxmox web UI or the command:"
        echo -e "   ${C_YELLOW}qm start ${TEMP_VM_ID}${C_RESET}"
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 2. Access the VM's console ('Serial Console 0'). Wait for the system to boot completely."
        echo -e "${C_BLUE}[INFO]${C_RESET}    Cloud-init might take some time on first boot."
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 3. Once logged in, execute the following commands inside the VM:"
        echo ""
        echo -e "   ${C_BLUE}# EN: Install/Update QEMU Guest Agent${C_RESET}"
        echo -e "   ${C_YELLOW}sudo apt update && sudo apt install -y qemu-guest-agent${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Start and enable the agent service${C_RESET}"
        echo -e "   ${C_YELLOW}sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Perform system upgrade and clean package cache${C_RESET}"
        echo -e "   ${C_YELLOW}sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean${C_RESET}"
        echo -e "   ${C_BLUE}# EN: (Optional) Configure console (font, layout) - INTERACTIVE${C_RESET}"
        echo -e "   ${C_YELLOW}sudo dpkg-reconfigure console-setup${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Remove SSH host keys${C_RESET}"
        echo -e "   ${C_YELLOW}sudo rm -f /etc/ssh/ssh_host_*${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Clear machine-id${C_RESET}"
        echo -e "   ${C_YELLOW}sudo truncate -s 0 /etc/machine-id${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Restore machine-id symlink${C_RESET}"
        echo -e "   ${C_YELLOW}sudo ln -sf /var/lib/dbus/machine-id /etc/machine-id${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Clean cloud-init logs and seed${C_RESET}"
        echo -e "   ${C_YELLOW}sudo cloud-init clean --logs --seed${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Create /etc/motd file with template information${C_RESET}"
        echo -e "   ${C_YELLOW}echo \"${motd_content_escaped}\" | sudo tee /etc/motd${C_RESET}"
        echo -e "   ${C_BLUE}# EN: Clear command history${C_RESET}"
        echo -e "   ${C_YELLOW}history -c && history -w && sudo history -c && sudo history -w${C_RESET}"
        echo ""
        echo -e "${C_BLUE}[INFO]${C_RESET} 4. After successfully executing all commands, shut down the VM from within:"
        echo -e "   ${C_YELLOW}sudo poweroff${C_RESET}"
        echo ""
        echo -e "${C_YELLOW}--------------------------------------------------------------------${C_RESET}"
        echo -e "${C_BOLD}EN: Press [Enter] key AFTER the VM has completely shut down to continue...${C_RESET}"
        read -r -p ""
    fi
}

# --- UA: Функція для автоматичного налаштування ВМ через user-data ---
# --- EN: Function to automatically configure VM using user-data ---
automate_vm_setup_with_userdata() {
    # UA: ПОПЕРЕДЖЕННЯ: Ця функція потребує тестування циклу очікування
    # EN: WARNING: This function requires testing of the wait loop
    log_info "Step 5a: Starting automated VM setup using cloud-init user-data..."

    local user_data_file
    user_data_file=$(mktemp /tmp/template-userdata-XXXXXX.yaml)
    # Trap handles cleanup

    local motd_content
    motd_content=$(printf "\n#################################################################\n#%71s#\n#  This VM template was created using a script from:            #\n#  %-60s #\n#%71s#\n#  OS Version: Ubuntu %-46s #\n#  Template Name: %-51s #\n#  Creation Date: %-51s #\n#%71s#\n#################################################################\n" \
                    "" "${GIT_REPO_URL}" "" \
                    "${UBUNTU_CODENAME} (${UBUNTU_ARCH})" \
                    "${FINAL_TEMPLATE_NAME}" \
                    "$(date '+%Y-%m-%d %H:%M:%S %Z')" "")

    log_info "Preparing user-data file: ${user_data_file}"
    cat << EOF > "$user_data_file"
#cloud-config
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
write_files:
  - path: /etc/motd
    content: |
${motd_content}
    permissions: '0644'
runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
  - [ rm, -f, /etc/ssh/ssh_host_* ]
  - [ truncate, -s, 0, /etc/machine-id ]
  - [ ln, -sf, /var/lib/dbus/machine-id, /etc/machine-id ]
  - [ cloud-init, clean, --logs, --seed ]
  - [ sh, -c, 'history -c && history -w || true' ]
  - [ poweroff, -f ]
EOF

    log_info "Attaching user-data to VM ${TEMP_VM_ID} from ${user_data_file}..."
    if qm set "${TEMP_VM_ID}" --cicustom "user=local:${user_data_file}"; then
        log_success "User-data attached successfully."
    else
        log_error "Failed to attach user-data (${user_data_file}) to VM ${TEMP_VM_ID}."
        # Trap handles cleanup
        exit 1
    fi

    log_info "Starting VM ${TEMP_VM_ID} to apply cloud-init configuration..."
    if qm start "${TEMP_VM_ID}"; then
        log_success "VM ${TEMP_VM_ID} started."
    else
        log_error "Failed to start VM ${TEMP_VM_ID}."
        # Trap handles cleanup
        exit 1
    fi

    log_info "Waiting for VM ${TEMP_VM_ID} to automatically shut down (timeout: 10 minutes)..."
    local wait_timeout=600; local wait_interval=15; local current_wait=0; local vm_status=""
    while [ "$current_wait" -lt "$wait_timeout" ]; do
        vm_status=$(qm status "${TEMP_VM_ID}" --verbose 2>/dev/null | grep status: | awk '{print $2}' || echo "unknown")
        if [ "$vm_status" == "stopped" ]; then
            log_success "VM ${TEMP_VM_ID} has shut down."; return 0 # Success
        elif [ "$vm_status" == "unknown" ]; then log_warn "Could not get VM status for ${TEMP_VM_ID} (maybe locked?). Waiting..."; sleep 5;
        else echo -n "."; fi # Running or other status
        sleep "$wait_interval"; current_wait=$((current_wait + wait_interval))
    done

    log_error "VM ${TEMP_VM_ID} did not shut down within the timeout period (${wait_timeout}s)."
    log_error "Please check the VM console for errors (qm terminal ${TEMP_VM_ID})."; exit 1
}

# --- UA: Функція для перетворення ВМ на шаблон, встановлення імені, тегів та нотаток ---
# --- EN: Function to convert VM to template, set name, tags, and notes ---
convert_vm_to_template() {
    log_info "Step 6: Converting VM ${TEMP_VM_ID} to template, applying final settings..."
    local vm_status
    vm_status=$(qm status "${TEMP_VM_ID}" --verbose 2>/dev/null | grep status: | awk '{print $2}' || echo "unknown")
    if [ "$vm_status" != "stopped" ]; then
        log_error "VM ${TEMP_VM_ID} is not stopped (current status: ${vm_status}). Cannot convert to template."
        exit 1
    fi
    log_info "VM ${TEMP_VM_ID} is stopped. Proceeding..."

    if qm template "${TEMP_VM_ID}"; then log_success "VM ${TEMP_VM_ID} successfully converted to template."; else log_error "Failed to convert VM to template." && exit 1; fi
    sleep 3

    log_info "Setting final template name to '${FINAL_TEMPLATE_NAME}'..."
    if qm set "${TEMP_VM_ID}" --name "${FINAL_TEMPLATE_NAME}"; then log_success "Template name set."; else log_warn "Failed to set template name."; fi

    local final_tags="${BASE_TAGS},${UBUNTU_CODENAME}"
    if [ -n "$ADDITIONAL_TAGS" ]; then [[ "${final_tags}" != *, ]] && final_tags="${final_tags},"; final_tags="${final_tags}${ADDITIONAL_TAGS}"; fi
    final_tags=$(echo "$final_tags" | sed 's/^,//; s/,$//; s/,,*/,/g')
    log_info "Applying tags: ${final_tags}"
    if qm set "${TEMP_VM_ID}" --tags "${final_tags}"; then log_success "Tags applied successfully."; else log_warn "Failed to apply tags."; fi

    local final_notes_content; local initial_notes
    initial_notes=$(qm config "${TEMP_VM_ID}" --current 2>/dev/null | grep '^description:' | sed 's/^description:[[:space:]]*//' | sed 's/\\n/\n/g' || echo '(initial notes not retrieved)')
    final_notes_content=$(printf "Template Source Information:\n----------------------------\nOS Version: %s (%s)\nTemplate Name: %s\n%s\nSource Repo: %s\nCreation Date: %s\n\nInitial VM creation notes:\n----------------------------\n%s" \
                               "${UBUNTU_CODENAME}" "${UBUNTU_ARCH}" "${FINAL_TEMPLATE_NAME}" "${SCRIPT_MARKER}" "${GIT_REPO_URL}" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "${initial_notes}")
    log_info "Applying final description (notes) to template..."
    if qm set "${TEMP_VM_ID}" --description "$(printf '%s' "$final_notes_content")"; then log_success "Final description (notes) applied."; else log_warn "Failed to apply final description (notes)."; fi

    log_success "Template ${FINAL_TEMPLATE_NAME} (VMID ${TEMP_VM_ID}) configuration complete."
}

# --- UA: Функція для очищення тимчасових файлів (завантаженого образу) ---
# --- EN: Function to clean up temporary files (downloaded image) ---
cleanup_temporary_files() {
    log_info "Step 7: Cleaning up temporary files..."
    log_info "Note: Any temporary user-data files created in /tmp are automatically removed on script exit by the 'trap' command."

    if [ "$FLAG_KEEP_IMAGE" == "true" ]; then
        log_info "Flag --keep-image is set. Skipping removal of downloaded image file: ${LOCAL_IMAGE_PATH}" && return 0
    fi

    if [ -f "$LOCAL_IMAGE_PATH" ]; then
        local question_delete_image_en="Do you want to remove the downloaded image file (${LOCAL_IMAGE_PATH})? (y/N): "
        local question_delete_image_uk="Бажаєте видалити завантажений файл образу (${LOCAL_IMAGE_PATH})? (y/N): "
        local confirm_delete=""
        if [ "$SCRIPT_LANG" == "uk" ]; then read -r -p "${C_YELLOW}${question_delete_image_uk}${C_RESET}" confirm_delete;
        else read -r -p "${C_YELLOW}${question_delete_image_en}${C_RESET}" confirm_delete; fi

        if [[ "$confirm_delete" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            log_info "Removing downloaded image file: ${LOCAL_IMAGE_PATH}"
            if rm -f "${LOCAL_IMAGE_PATH}"; then log_success "Downloaded image file removed."; else log_warn "Could not remove image file."; fi
        else
             log_info "Skipping removal of the downloaded image file."
        fi
    else
        log_info "Downloaded image file (${LOCAL_IMAGE_PATH}) not found. No cleanup needed for image."
    fi
}

# --- UA: Функція для фіналізації параметрів скрипту після розбору аргументів ---
# --- EN: Function to finalize script parameters after argument parsing ---
finalize_script_parameters() {
    log_info "Finalizing script parameters..." # Це повідомлення з finalize_script_parameters

    set_ubuntu_image_details "$UBUNTU_CODENAME" "$UBUNTU_ARCH"

    local iso_info_raw
    local detected_iso_storage_id=""
    local detected_iso_storage_path=""

    if [ -z "$DOWNLOAD_DIR_USER_SPECIFIED" ]; then
        # UA: Лог перед викликом функції, що повертає значення
        # EN: Log before calling the function that returns a value
        log_info "Attempting to find a Proxmox storage suitable for ISO/image downloads..."
        iso_info_raw=$(get_iso_storage_info) # Ця функція тепер має логувати в stderr

        if [ -n "$iso_info_raw" ]; then
            detected_iso_storage_id=$(echo "$iso_info_raw" | cut -d':' -f1)
            detected_iso_storage_path=$(echo "$iso_info_raw" | cut -d':' -f2-) # cut -f2- для шляхів з ':'
            DOWNLOAD_DIR="$detected_iso_storage_path"
            # UA: Логуємо вже після отримання чистих значень
            # EN: Log after getting clean values
            log_success "Found suitable active ISO storage: ID='${detected_iso_storage_id}', Path='${DOWNLOAD_DIR}'"
            log_info "Using auto-detected download directory: ${DOWNLOAD_DIR}"
        else
            # UA: get_iso_storage_info виведе своє попередження в stderr, якщо нічого не знайдено
            # EN: get_iso_storage_info will output its warning to stderr if nothing found
            DOWNLOAD_DIR="$DEFAULT_DOWNLOAD_DIR"
            log_warn "Could not auto-detect ISO storage path. Using default download directory: ${DOWNLOAD_DIR}."
        fi
    else
        log_info "User specified download directory: ${DOWNLOAD_DIR}"
    fi

    if [ -z "$PROXMOX_STORAGE_USER_SPECIFIED" ]; then
        if [ -n "$detected_iso_storage_id" ]; then # Використовуємо чистий ID, отриманий вище
            log_info "Checking if auto-detected ISO storage '${detected_iso_storage_id}' can also store VM images..."
            if check_storage_content_type "${detected_iso_storage_id}" "images"; then
                PROXMOX_STORAGE_ACTUAL="${detected_iso_storage_id}"
                # UA: check_storage_content_type вже логує успіх/невдачу своєї перевірки
                # EN: check_storage_content_type already logs the success/failure of its check
                log_info "Using auto-detected ISO storage '${PROXMOX_STORAGE_ACTUAL}' for VM disks as it supports 'images' content."
            else
                PROXMOX_STORAGE_ACTUAL="${DEFAULT_PROXMOX_STORAGE}"
                log_warn "Auto-detected ISO storage '${detected_iso_storage_id}' does not support 'images' content (or is inactive)."
                log_warn "Falling back to default Proxmox storage for VM disks: ${PROXMOX_STORAGE_ACTUAL}."
            fi
        else
            PROXMOX_STORAGE_ACTUAL="${DEFAULT_PROXMOX_STORAGE}"
            log_warn "No specific ISO storage auto-detected for download. Using default Proxmox storage for VM disks: ${PROXMOX_STORAGE_ACTUAL}."
        fi
    else
        log_info "User specified Proxmox storage for VM disks: ${PROXMOX_STORAGE_ACTUAL}"
    fi

    IMAGE_URL="${IMAGE_BASE_URL}/${IMAGE_PATH_SEGMENT}/${IMAGE_FILENAME}"
    LOCAL_IMAGE_PATH="${DOWNLOAD_DIR}/${IMAGE_FILENAME}"

    if [ -z "$FINAL_TEMPLATE_NAME" ]; then FINAL_TEMPLATE_NAME="${TEMPLATE_NAME_PREFIX}-${UBUNTU_CODENAME}-cloudinit"; fi
    if [ -z "$PROXMOX_NODE" ]; then if command -v hostname &> /dev/null; then PROXMOX_NODE=$(hostname -f); else log_error "Proxmox node not specified (--node)." && exit 1; fi; fi
    if [ -z "$TEMP_VM_ID" ]; then
        local highest_vmid
        highest_vmid=$( (qm list | awk 'NR>1 {print $1}' | sort -n | tail -n 1) || echo 0)
        if [ "$highest_vmid" -lt 9000 ]; then TEMP_VM_ID="${VMID_PREFIX}01";
        else TEMP_VM_ID=$((highest_vmid + 1)); fi
        if [ "$TEMP_VM_ID" -lt 100 ]; then TEMP_VM_ID="${VMID_PREFIX}01"; fi
        log_warn "Temporary VM ID not specified via --vmid. Auto-selected: ${TEMP_VM_ID}."
    fi
    log_info "Finalized script parameters successfully."
}

# --- UA: Ініціалізація та розбір аргументів ---
# --- EN: Initialization and Argument Parsing ---
SCRIPT_LANG="${DEFAULT_SCRIPT_LANG}"
SCRIPT_MARKER="${DEFAULT_SCRIPT_MARKER}"
GIT_REPO_URL="${DEFAULT_GIT_REPO_URL}"
UBUNTU_CODENAME="${DEFAULT_UBUNTU_CODENAME}"
UBUNTU_ARCH="${DEFAULT_UBUNTU_ARCH}"
IMAGE_BASE_URL="${DEFAULT_IMAGE_BASE_URL}"
DOWNLOAD_DIR=""
VMID_PREFIX="${DEFAULT_VMID_PREFIX}"
TEMPLATE_NAME_PREFIX="${DEFAULT_TEMPLATE_NAME_PREFIX}"
VM_CORES="${DEFAULT_VM_CORES}"
VM_MEMORY="${DEFAULT_VM_MEMORY}"
VM_DISK_SIZE="${DEFAULT_VM_DISK_SIZE}"
VM_BRIDGE="${DEFAULT_VM_BRIDGE}"
PROXMOX_STORAGE_ACTUAL=""
PROXMOX_NODE="${DEFAULT_PROXMOX_NODE}"
SSH_PUB_KEY_FILE="${DEFAULT_SSH_PUB_KEY_FILE}"
BASE_TAGS="${DEFAULT_BASE_TAGS}"
ADDITIONAL_TAGS=""
TEMP_VM_ID=""
FINAL_TEMPLATE_NAME=""
PROXMOX_STORAGE_USER_SPECIFIED=""
DOWNLOAD_DIR_USER_SPECIFIED=""
parsed_codename=""
FLAG_AUTO_SETUP="false"
FLAG_FORCE_CLEANUP_VM="false"
FLAG_KEEP_IMAGE="false"

# UA: Встановлюємо trap для очищення тимчасового файлу user-data
# EN: Set trap to clean up temporary user-data file
# EN: Use a function for cleaner trap handling
cleanup_on_exit() {
    log_info "Running cleanup tasks on exit..."
    rm -f /tmp/template-userdata-*.yaml
}
trap cleanup_on_exit EXIT INT TERM HUP

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -c|--codename) parsed_codename="$2"; UBUNTU_CODENAME="$2"; shift 2 ;;
        -a|--arch) UBUNTU_ARCH="$2"; shift 2 ;;
        -s|--storage) PROXMOX_STORAGE_ACTUAL="$2"; PROXMOX_STORAGE_USER_SPECIFIED="true"; shift 2 ;;
        -n|--node) PROXMOX_NODE="$2"; shift 2 ;;
        -i|--vmid) TEMP_VM_ID="$2"; shift 2 ;;
        -t|--template-name) FINAL_TEMPLATE_NAME="$2"; shift 2 ;;
        --cores) VM_CORES="$2"; shift 2 ;;
        --memory) VM_MEMORY="$2"; shift 2 ;;
        --disk-size) VM_DISK_SIZE="$2"; shift 2 ;;
        --bridge) VM_BRIDGE="$2"; shift 2 ;;
        --ssh-key-file) SSH_PUB_KEY_FILE="$2"; shift 2 ;;
        --image-base-url) IMAGE_BASE_URL="$2"; shift 2 ;;
        --download-dir) DOWNLOAD_DIR="$2"; DOWNLOAD_DIR_USER_SPECIFIED="true"; shift 2 ;;
        --add-tags) ADDITIONAL_TAGS="$2"; shift 2 ;;
        --auto-vm-setup) FLAG_AUTO_SETUP="true"; shift ;;
        --force-cleanup-vm) FLAG_FORCE_CLEANUP_VM="true"; shift ;;
        --keep-image) FLAG_KEEP_IMAGE="true"; shift ;;
        --lang)
             if [[ "$2" == "en" || "$2" == "uk" ]]; then SCRIPT_LANG="$2";
             else log_warn "Invalid language code '$2'. Using default '${DEFAULT_SCRIPT_LANG}'."; fi
             shift 2 ;;
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# --- UA: Викликаємо функцію для фіналізації параметрів ПІСЛЯ розбору аргументів ---
# --- EN: Call the function to finalize parameters AFTER parsing arguments ---
finalize_script_parameters


# --- UA: Головна функція ---
# --- EN: Main function ---
main() {
    log_info "Starting Ubuntu Cloud-Init Template Creation Script..."
    log_info "-----------------------------------------------------"
    log_info "Configuration (${SCRIPT_LANG} language output selected):"
    log_info "  Ubuntu Codename:        ${UBUNTU_CODENAME} (${UBUNTU_ARCH})"
    log_info "  Image Base URL:         ${IMAGE_BASE_URL}"
    log_info "  Image Path Segment:     ${IMAGE_PATH_SEGMENT}"
    log_info "  Image Filename:         ${IMAGE_FILENAME}"
    log_info "  Full Image URL:         ${IMAGE_URL}"
    log_info "  Download Directory:     ${DOWNLOAD_DIR}"
    log_info "  Local Image Path:       ${LOCAL_IMAGE_PATH}"
    log_info "  Temporary VM ID:        ${TEMP_VM_ID}"
    log_info "  Final Template Name:    ${FINAL_TEMPLATE_NAME}"
    log_info "  Proxmox Node:           ${PROXMOX_NODE}"
    log_info "  Proxmox Storage (VMs):  ${PROXMOX_STORAGE_ACTUAL}"
    log_info "  VM Resources:           ${VM_CORES} Cores, ${VM_MEMORY}MB RAM, ${VM_DISK_SIZE} Disk"
    log_info "  VM Network Bridge:      ${VM_BRIDGE}"
    log_info "  SSH Public Key File:    ${SSH_PUB_KEY_FILE} (Note: Key not automatically injected into template)"
    log_info "  Base Tags:              ${BASE_TAGS}"
    log_info "  Additional Tags:        ${ADDITIONAL_TAGS:-*(none)*}"
    log_info "  Git Repo URL:           ${GIT_REPO_URL}"
    log_info "  Automated VM Setup:     ${FLAG_AUTO_SETUP}"
    log_info "  Force VM Cleanup:       ${FLAG_FORCE_CLEANUP_VM}"
    log_info "  Keep Image File:        ${FLAG_KEEP_IMAGE}"
    log_info "-----------------------------------------------------"

    # 0. Перевірка середовища та існуючого шаблону
    check_environment
    check_existing_template "${FINAL_TEMPLATE_NAME}"

    # 1. Крок 1: Завантаження образу та перевірка суми
    download_image

    # 2. Крок 2 та 2.1: Створення тимчасової ВМ та EFI диска
    create_temp_vm

    # 3. Крок 3: Імпорт диска
    import_vm_disk

    # 4. Крок 4: Налаштування ВМ
    configure_vm_settings

    # 5. Крок 5: Автоматичне або ручне налаштування всередині ВМ
    #if [ "$FLAG_AUTO_SETUP" == "true" ]; then
    #    automate_vm_setup_with_userdata
    #else
    #    prompt_for_manual_steps
    #fi

    # 6. Крок 6: Перетворення на шаблон, додавання тегів та нотаток
    #convert_vm_to_template

    # 7. Крок 7: Очищення
    #cleanup_temporary_files

    #log_info "-----------------------------------------------------"
    #log_success "Script finished successfully!"
    #log_success "Template '${FINAL_TEMPLATE_NAME}' (VMID ${TEMP_VM_ID}) should be ready in Proxmox."
    #log_info "-----------------------------------------------------"
}

# --- UA: Виклик головної функції ---
# --- EN: Call the main function ---
main "$@"

# UA: Знімаємо trap перед нормальним виходом (вже виконано в cleanup_on_exit, якщо вона викликалась)
# EN: Remove trap before normal exit (already done in cleanup_on_exit if it was called)
trap - EXIT INT TERM HUP
exit 0
