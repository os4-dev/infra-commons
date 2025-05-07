#!/usr/bin/env bash

# UA: Скрипт для встановлення допоміжних утиліт для роботи з інфраструктурою.
# UA: Включає інструменти для роботи з Proxmox (опосередковано), OpenTofu,
# UA: обробки JSON, завантаження файлів, генерації паролів та роботи з образами ВМ.
# UA: Призначений для запуску на Debian-подібних системах (Ubuntu, Debian).
# UA: Для інших систем команди встановлення пакетів можуть відрізнятися.
# EN: Script to install auxiliary utilities for working with infrastructure.
# EN: Includes tools for working with Proxmox (indirectly), OpenTofu,
# EN: JSON processing, file downloading, password generation, and VM image manipulation.
# EN: Designed for Debian-based systems (Ubuntu, Debian).
# EN: Package installation commands may differ on other systems.

# UA: Зупиняти скрипт при першій помилці
# EN: Stop script on first error
set -e
# UA: Вважати помилкою використання неініціалізованих змінних
# EN: Treat unset variables as an error
set -u
# UA: Вважати помилкою, якщо будь-яка команда в конвеєрі (pipe) завершується з помилкою
# EN: Treat any command in a pipeline failing as an error
set -o pipefail

# UA: Кольори для виводу
# EN: Colors for output
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'

SUDO_CMD="" # EN: Will be set by check_sudo

# UA: Функції для логування
# EN: Logging functions
log_info() {
    echo -e "${C_BLUE}[INFO]${C_RESET} $1"
}

log_success() {
    echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"
}

log_warn() {
    echo -e "${C_YELLOW}[WARN]${C_RESET} $1"
}

log_error() {
    echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2 # EN: Output errors to stderr
}

# UA: Функція для виведення списку утиліт
# EN: Function to display the list of manageable utilities
list_utils() {
    echo -e "${C_BOLD}This script can manage the installation of the following utilities:${C_RESET}"
    echo ""
    echo -e "  ${C_GREEN}Core Utilities (installed by default unless skipped):${C_RESET}"
    echo "    - wget          (File downloader)"
    echo "    - curl          (HTTP requests and file downloader)"
    echo "    - jq            (Command-line JSON processor)"
    echo "    - qemu-utils    (Contains qemu-img for disk image manipulation - skipped on Proxmox VE hosts)"
    echo "    - virt-what     (Detects if running in a VM)"
    echo "    - pwgen         (Password generator)"
    echo ""
    echo -e "  ${C_YELLOW}Optional Components (installable via flags):${C_RESET}"
    echo "    - SSH Key       (Checks for existing keys or offers to generate new ED25519 keys)"
    echo "                    (Use --no-ssh-keygen to skip)"
    echo "    - sshpass       (Non-interactive SSH with password - USE WITH CAUTION)"
    echo "                    (Use --install-sshpass to install)"
    echo "    - Python Tools  (Python3, pip, and 'proxmoxer' library for Proxmox API)"
    echo "                    (Use --install-python to install)"
    echo ""
}


# UA: Функція для виведення довідки
# EN: Function to display help message
show_help() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "This script installs auxiliary utilities for infrastructure work on Debian-based systems."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message and exit."
    echo "  -l, --list-utils        List all utilities that can be installed by this script and exit."
    echo "  --no-ssh-keygen         Skip SSH key generation/check."
    echo "  --install-python        Install Python3, pip, and 'proxmoxer' library."
    echo "  --install-sshpass       Install 'sshpass' (USE WITH CAUTION)."
    # UA: Можна додати --no-core-utils, якщо потрібно буде пропускати встановлення базових утиліт
    # EN: Could add --no-core-utils if skipping core utils installation becomes a requirement
    echo ""
    echo "The script will attempt to use 'sudo' for package installations if not run as root."
}

# UA: Перевірка, чи скрипт запущено від імені root
# EN: Check if the script is run as root
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        # UA: Не виводимо попередження, якщо користувач просто запросив --help або --list-utils
        # EN: Don't show warning if user just asked for --help or --list-utils
        if [[ "${SHOULD_PERFORM_INSTALL:-true}" == "true" ]]; then
            log_warn "Some commands require superuser privileges (sudo)."
            log_warn "The script will attempt to use 'sudo' automatically."
        fi
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi
}

# UA: Функція для оновлення списку пакетів
# EN: Function to update package lists
update_package_lists() {
    log_info "Updating package lists (apt update)..."
    if ${SUDO_CMD} apt update -qq; then # EN: -qq for quieter output
        log_success "Package lists updated successfully."
    else
        log_error "Failed to update package lists. Further installations might fail."
        exit 1
    fi
}

# UA: Функція для встановлення пакету, якщо він ще не встановлений
# EN: Function to install a package if it's not already installed
install_package() {
    local package_name="$1"
    local package_display_name="${2:-$1}" # EN: Optional display name for output

    log_info "Checking if ${package_display_name} is installed..."
    if dpkg -s "$package_name" >/dev/null 2>&1; then
        log_success "${package_display_name} is already installed (version: $(dpkg-query -W -f='${Version}' "$package_name"))."
    else
        log_info "Installing ${package_display_name} ($package_name)..."
        if ${SUDO_CMD} apt install -y "$package_name"; then
            log_success "${package_display_name} installed successfully."
        else
            log_error "Failed to install ${package_display_name} ($package_name)."
            # EN: You might want to exit here or return an error code: return 1
        fi
    fi
}

# UA: Функція для перевірки, чи це хост Proxmox VE
# EN: Function to check if this is a Proxmox VE host
is_proxmox_host() {
    # UA: Проста перевірка: шукаємо команду pveversion або каталог /etc/pve
    # EN: Simple check: look for pveversion command or /etc/pve directory
    if command -v pveversion >/dev/null 2>&1 || [ -d "/etc/pve" ]; then
        return 0 # true, it's likely a Proxmox host
    else
        return 1 # false
    fi
}


# UA: Функція для встановлення основних утиліт
# EN: Function to install core utilities
install_core_utils() {
    log_info "Installing core utilities..."
    install_package "wget" "wget (for file downloads)"
    install_package "curl" "curl (for HTTP requests and file downloads)"
    install_package "jq" "jq (command-line JSON processor)"
    install_package "virt-what" "virt-what (detects if running in a VM)"
    install_package "pwgen" "pwgen (password generator)"

    # UA: Встановлюємо qemu-utils ТІЛЬКИ якщо це НЕ хост Proxmox VE
    # EN: Install qemu-utils ONLY if this is NOT a Proxmox VE host
    if is_proxmox_host; then
        log_warn "Detected Proxmox VE host. Checking for 'qemu-img' command instead of installing 'qemu-utils' package."
        if command -v qemu-img >/dev/null 2>&1; then
            log_success "'qemu-img' command is already available (likely from Proxmox packages)."
        else
            # UA: Це дуже малоймовірно на робочому Proxmox
            # EN: This is very unlikely on a working Proxmox
            log_error "'qemu-img' command not found, and installing 'qemu-utils' on Proxmox is unsafe due to conflicts."
            log_error "Please ensure Proxmox QEMU packages (like pve-qemu-kvm) are correctly installed."
            # UA: Можна розглянути можливість зупинки скрипту тут
            # EN: Consider exiting the script here
            # exit 1
        fi
    else
        # UA: Це не хост Proxmox, безпечно встановлювати qemu-utils
        # EN: Not a Proxmox host, safe to install qemu-utils
        log_info "Not a Proxmox VE host. Proceeding with 'qemu-utils' installation..."
        install_package "qemu-utils" "qemu-utils (contains qemu-img for disk image manipulation)"
    fi
}

# UA: Функція для встановлення sshpass (опціонально)
# EN: Function to install sshpass (optional)
install_sshpass_utility() {
    log_info "Installing 'sshpass' (USE WITH CAUTION)..."
    # UA: УВАГА: Використовуйте з великою обережністю! SSH-ключі є значно безпечнішим варіантом.
    # EN: WARNING: Use with extreme caution! SSH keys are a much more secure option.
    install_package "sshpass"
}

# UA: Функція для перевірки/генерації SSH ключа
# EN: Function for SSH key check/generation
setup_ssh_keys() {
    local SSH_KEY_PATH_ED25519="$HOME/.ssh/id_ed25519"
    local SSH_KEY_PATH_RSA="$HOME/.ssh/id_rsa"

    log_info "Checking for existing SSH keys..."
    if [ ! -f "$SSH_KEY_PATH_ED25519" ] && [ ! -f "$SSH_KEY_PATH_RSA" ]; then
        log_warn "No SSH key found in standard locations ($SSH_KEY_PATH_ED25519 or $SSH_KEY_PATH_RSA)."
        # UA: Використовуємо read -r -p, але можна зробити це неінтерактивним за замовчуванням
        # EN: Using read -r -p, but could default to non-interactive
        read -r -p "Do you want to generate a new ED25519 SSH key now? (y/N): " generate_ssh_key_response
        if [[ "$generate_ssh_key_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            local user_email=""
            read -r -p "Enter your email for the SSH key comment (or leave blank for default): " user_email
            if [ -z "$user_email" ]; then
                user_email="$(whoami)@$(hostname)-$(date +%Y%m%d)"
            fi
            log_info "Generating ED25519 SSH key for '$user_email'..."
            # UA: Створюємо каталог .ssh, якщо його немає
            # EN: Create .ssh directory if it doesn't exist
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            ssh-keygen -t ed25519 -f "$SSH_KEY_PATH_ED25519" -N "" -C "$user_email"
            log_success "SSH key generated successfully: $SSH_KEY_PATH_ED25519 and $SSH_KEY_PATH_ED25519.pub"
            log_info "Remember to add the public key ($SSH_KEY_PATH_ED25519.pub) to authorized keys on your servers."
        fi
    else
        log_success "SSH key(s) found."
        if [ -f "$SSH_KEY_PATH_ED25519" ]; then
            log_info "Found ED25519 key: $SSH_KEY_PATH_ED25519.pub"
        fi
        if [ -f "$SSH_KEY_PATH_RSA" ]; then
            log_info "Found RSA key: $SSH_KEY_PATH_RSA.pub"
        fi
    fi
}

# UA: Функція для встановлення Python та бібліотек для Proxmox API (опціонально)
# EN: Function to install Python and Proxmox API libraries (optional)
install_python_for_proxmox() {
    log_info "Installing Python3, pip, and 'proxmoxer' library..."
    install_package "python3"
    install_package "python3-pip" "pip3 (Python package manager)"
    if command -v pip3 &> /dev/null; then
        log_info "Checking if 'proxmoxer' library is installed..."
        # UA: Використовуємо grep для перевірки, оскільки pip show може мати ненульовий вихід, якщо пакет не знайдено
        # EN: Using grep for check, as pip show might have non-zero exit if package not found
        if pip3 list --format=freeze | grep -i "^proxmoxer==" > /dev/null 2>&1; then
            log_success "'proxmoxer' is already installed."
        else
            log_info "Installing Python library 'proxmoxer'..."
            # UA: Спробуємо без sudo спочатку, якщо не вийде - тоді з sudo (або завжди з sudo, як було)
            # EN: Try without sudo first, if it fails, then with sudo (or always with sudo as before)
            if pip3 install proxmoxer || ${SUDO_CMD} pip3 install proxmoxer; then
                log_success "'proxmoxer' installed successfully."
            else
                log_error "Failed to install 'proxmoxer'."
            fi
        fi
    else
        log_warn "pip3 not found. Cannot install 'proxmoxer'."
    fi
}

# UA: Головна функція скрипту
# EN: Main function of the script
main() {
    # UA: Ініціалізація прапорців для опціональних дій
    # EN: Initialize flags for optional actions
    local flag_skip_ssh_keygen=false
    local flag_install_python=false
    local flag_install_sshpass=false
    # UA: Прапорець, що вказує, чи потрібно виконувати встановлення
    # EN: Flag to indicate if installation actions should be performed
    SHOULD_PERFORM_INSTALL=true


    # UA: Обробка аргументів командного рядка
    # EN: Parse command-line arguments
    if [[ $# -eq 0 ]]; then
        # EN: No arguments provided, proceed with default installation
        : # EN: Placeholder, default behavior is to install
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -h|--help)
                    show_help
                    SHOULD_PERFORM_INSTALL=false # EN: Don't perform install actions for --help
                    exit 0
                    ;;
                -l|--list-utils)
                    list_utils
                    SHOULD_PERFORM_INSTALL=false # EN: Don't perform install actions for --list-utils
                    exit 0
                    ;;
                --no-ssh-keygen)
                    flag_skip_ssh_keygen=true
                    # log_info "SSH key generation/check will be skipped." # Log later if install happens
                    shift
                    ;;
                --install-python)
                    flag_install_python=true
                    # log_info "Python and 'proxmoxer' installation will be attempted." # Log later
                    shift
                    ;;
                --install-sshpass)
                    flag_install_sshpass=true
                    # log_info "'sshpass' installation will be attempted (USE WITH CAUTION)." # Log later
                    shift
                    ;;
                *)
                    log_error "Unknown option: $1"
                    show_help
                    exit 1
                    ;;
            esac
        done
    fi

    # UA: Виконуємо дії тільки якщо не було запиту на --help або --list-utils
    # EN: Perform actions only if --help or --list-utils was not requested
    if [ "$SHOULD_PERFORM_INSTALL" = true ]; then
        # UA: Виводимо інформацію про опції тут, коли точно знаємо, що будемо встановлювати
        # EN: Log options here, when we know we're actually installing
         if [ "$flag_skip_ssh_keygen" = true ]; then log_info "SSH key generation/check will be skipped (--no-ssh-keygen)."; fi
         if [ "$flag_install_python" = true ]; then log_info "Python and 'proxmoxer' installation requested (--install-python)."; fi
         if [ "$flag_install_sshpass" = true ]; then log_info "'sshpass' installation requested (--install-sshpass) - USE WITH CAUTION."; fi

        check_sudo
        update_package_lists
        install_core_utils

        if [ "$flag_install_sshpass" = true ]; then
            install_sshpass_utility
        fi

        if [ "$flag_skip_ssh_keygen" = false ]; then
            setup_ssh_keys
        else
            log_info "Skipping SSH key setup."
        fi

        if [ "$flag_install_python" = true ]; then
            install_python_for_proxmox
        fi

        log_info "-----------------------------------------------------"
        log_success "Auxiliary utilities installation process finished."
        log_info "-----------------------------------------------------"
    fi
}

# UA: Виклик головної функції з усіма переданими аргументами
# EN: Call the main function with all passed arguments
main "$@"

# UA: Повертаємо 0 для успішного завершення
# EN: Exit with 0 on successful completion
exit 0
