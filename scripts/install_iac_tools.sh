#!/bin/bash

# Виходити негайно, якщо команда завершується з помилкою
# Exit immediately if a command exits with a non-zero status
set -e

# --- Початок блоку обробки помилок ---
# --- Start of error handling block ---
handle_error() {
  local exit_code=$?
  local line_num=$1
  local command="${BASH_COMMAND}"
  echo "------------------------------------------------------------" >&2
  echo "[Main Script] ERROR: Script failed on line $line_num with exit code $exit_code." >&2
  echo "[Main Script] Failing command segment: $command" >&2
  echo "------------------------------------------------------------" >&2
}
trap 'handle_error $LINENO' ERR
# --- Кінець блоку обробки помилок ---
# --- End of error handling block ---

# === Змінні та Налаштування / Variables and Settings ===
INSTALL_DEV_TOOLS=false # Прапорець для встановлення інструментів розробки / Flag for installing dev tools
DEV_TOOLS_ONLY=false    # Прапорець для встановлення ТІЛЬКИ інструментів розробки / Flag for installing ONLY dev tools
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)" # Директорія скрипта / Script directory

# === Функції / Functions ===

# Функція для виводу довідки
# Function to print usage information
print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Installs standard IaC tools (Ansible, OpenTofu) and their dependencies."
  echo ""
  echo "Options:"
  echo "  --dev         Additionally install common development tools (e.g., shellcheck)"
  echo "  --dev-only    Install ONLY the common development tools, skipping IaC tools"
  echo "  -h, --help    Display this help message"
  echo ""
  echo "Note: This script must be run with root privileges (e.g., using sudo)."
  echo ""
  echo "---" # Ukrainian below
  echo ""
  echo "Використання: $0 [ОПЦІЇ]"
  echo "Встановлює стандартні IaC інструменти (Ansible, OpenTofu) та їх залежності."
  echo ""
  echo "Опції:"
  echo "  --dev         Додатково встановити поширені інструменти розробки (напр., shellcheck)"
  echo "  --dev-only    Встановити ТІЛЬКИ поширені інструменти розробки, пропускаючи IaC інструменти"
  echo "  -h, --help    Показати це повідомлення довідки"
  echo ""
  echo "Примітка: Скрипт потрібно запускати з правами root (напр., через sudo)."
}


# Перевірка запуску від імені root
# Check if running as root
check_root() {
  echo "--> Verifying root privileges..."
  # Перевіряємо ефективний UID / Check effective UID
  if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Please run this script as root (using sudo)." >&2
    print_usage >&2 # Показуємо довідку при помилці / Show usage on error
    exit 1
  fi
  echo "Root privileges verified."
}

# Оновлення пакетів та встановлення залежностей
# Update packages and install dependencies
prepare_system() {
  echo "--> Step 1 & 2: Updating package list and installing dependencies..."
  # Оновлення / Update
  # Note: apt-get update might be run again by install_dev_tools.sh if called
  apt-get update

  # Встановлення залежностей / Install dependencies
  apt-get install -y wget gpg curl lsb-release apt-transport-https ca-certificates
  echo "System preparation complete (update & dependencies installed)."
}

# Визначення кодового імені та встановлення Ansible
# Determine codename and install Ansible
install_ansible() {
  # Використовуємо шлях від директорії основного скрипта
  # Use path relative to the main script's directory
  local ansible_script="${SCRIPT_DIR}/install_ansible.sh"
  local ansible_ppa_codename=""

  echo "--> Step 3 & 4: Determining codename and installing Ansible..."
  # --- Визначення кодового імені PPA для Ansible ---
  # --- Determine PPA codename for Ansible ---
  echo "Determining OS details for Ansible PPA..."
  # Перевірка наявності lsb_release / Check if lsb_release exists
  if ! command -v lsb_release &> /dev/null; then
      echo "Error: lsb_release command not found." >&2
      # Dependencies might not be installed if --dev-only was intended but failed,
      # so this check is still relevant.
      exit 1
  fi
  local os_codename
  local os_id
  # Отримання ID та кодового імені ОС / Get OS ID and codename
  os_codename=$(lsb_release -cs)
  os_id=$(lsb_release -is | tr '[:upper:]' '[:lower:]') # Переводимо в нижній регістр / Convert to lower case

  echo "Detected OS: $os_id, Codename: $os_codename"

  # Мапінг кодових імен Debian/Ubuntu для PPA Ansible / Map Debian/Ubuntu codenames for Ansible PPA
  if [ "$os_id" == "debian" ]; then
    case "$os_codename" in
      "bookworm") ansible_ppa_codename="jammy" ;; # Debian 12 -> Ubuntu 22.04
      "bullseye") ansible_ppa_codename="focal" ;; # Debian 11 -> Ubuntu 20.04
      "buster")   ansible_ppa_codename="bionic" ;; # Debian 10 -> Ubuntu 18.04
      *)
        # Якщо немає прямого співпадіння, спробуємо використати ім'я як є (може не спрацювати)
        # If no direct match, try using the codename as is (might not work)
        echo "Warning: No direct PPA mapping found for Debian '$os_codename'. Using '$os_codename' itself." >&2
        ansible_ppa_codename="$os_codename"
        ;;
    esac
  elif [ "$os_id" == "ubuntu" ]; then
    # Для Ubuntu використовуємо власне кодове ім'я / For Ubuntu, use its own codename
    ansible_ppa_codename="$os_codename"
  else
    echo "Error: Could not determine supported distribution (Debian or Ubuntu required for this PPA method)." >&2
    exit 1
  fi

  # Перевірка, чи вдалося визначити кодове ім'я / Verify if codename was determined
  if [ -z "$ansible_ppa_codename" ]; then
      echo "Error: Failed to determine PPA codename for Ansible." >&2
      exit 1
  fi
  echo "Using PPA codename '$ansible_ppa_codename' for Ansible."

  # --- Запуск встановлення Ansible ---
  # --- Run Ansible installation ---
  echo "Running Ansible installation script ($ansible_script)..."
  # Перевірка існування та прав на виконання скрипта / Check if script exists and is executable
  if [ -f "$ansible_script" ]; then
    # Додаємо права на виконання (про всяк випадок) / Add execute permissions (just in case)
    chmod +x "$ansible_script"
    # Викликаємо скрипт, передаючи визначене кодове ім'я
    # Call the script, passing the determined codename
    "$ansible_script" "$ansible_ppa_codename"
  else
    echo "Error: Script $ansible_script not found!" >&2
    exit 1
  fi
  echo "Ansible installation step finished."
}

# Встановлення OpenTofu
# Install OpenTofu
install_opentofu() {
  # Використовуємо шлях від директорії основного скрипта
  # Use path relative to the main script's directory
  local opentofu_script="${SCRIPT_DIR}/install_opentofu.sh"
  echo "--> Step 5: Running OpenTofu installation ($opentofu_script)..."
  # Перевірка існування та прав на виконання скрипта / Check if script exists and is executable
  if [ -f "$opentofu_script" ]; then
    # Додаємо права на виконання / Add execute permissions
    chmod +x "$opentofu_script"
    # Викликаємо скрипт OpenTofu / Call the OpenTofu script
    "$opentofu_script"
  else
    echo "Error: Script $opentofu_script not found!" >&2
    exit 1
  fi
  echo "OpenTofu installation step finished."
}

# --- Обробка Аргументів / Argument Parsing ---
parse_arguments() {
  # Проходимо по всіх аргументах / Loop through all arguments
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      --dev)
        INSTALL_DEV_TOOLS=true
        echo "[Args] Development tools installation requested via --dev flag."
        shift # переходимо до наступного аргументу / move past argument
        ;;
      --dev-only)
        # Якщо вказано --dev-only, то автоматично вмикаємо і --dev
        # If --dev-only is specified, automatically enable --dev as well
        INSTALL_DEV_TOOLS=true
        DEV_TOOLS_ONLY=true
        echo "[Args] ONLY Development tools installation requested via --dev-only flag."
        shift # переходимо до наступного аргументу / move past argument
        ;;
      -h|--help)
        print_usage
        # Знімаємо trap перед виходом, щоб не було повідомлення про помилку
        # Remove trap before exit to avoid error message
        trap - ERR
        exit 0 # Виходимо після показу довідки / Exit after showing help
        ;;
      *)    # невідома опція / unknown option
        echo "[Args] Error: Unknown option '$1'" >&2
        print_usage >&2
        exit 1
        ;;
    esac
  done
}

# === Основна логіка / Main Logic ===
main() {
  # Обробляємо аргументи командного рядка, передані скрипту
  # Process command line arguments passed to the script
  parse_arguments "$@"

  # Перевірка прав root потрібна завжди для встановлення пакетів
  # Check root privileges always needed for package installation
  check_root

  # Якщо НЕ режим --dev-only, встановлюємо основні інструменти
  # If NOT in --dev-only mode, install the main tools
  if [ "$DEV_TOOLS_ONLY" = false ]; then
    echo "=== Starting FULL IaC tools installation (Ansible, OpenTofu) ==="
    prepare_system    # Оновлення та встановлення залежностей / Update and install dependencies
    install_ansible   # Встановлення Ansible / Install Ansible
    install_opentofu  # Встановлення OpenTofu / Install OpenTofu
  else
    echo "=== Starting DEV-ONLY tools installation ==="
    # Можливо, тут варто запустити apt-get update, якщо prepare_system пропущено
    # Maybe run apt-get update here if prepare_system is skipped
    # Але install_dev_tools.sh вже робить update всередині
    # But install_dev_tools.sh already does update inside
    echo "--> Skipping IaC tools installation due to --dev-only flag."
  fi

  # Встановлення інструментів розробки (якщо запитано через --dev або --dev-only)
  # Install Development Tools (if requested via --dev or --dev-only)
  if [ "$INSTALL_DEV_TOOLS" = true ]; then
    echo "--> Running Developer Tools installation..."
    local dev_tools_script="${SCRIPT_DIR}/install_dev_tools.sh"
    # Перевіряємо, чи існує скрипт і чи він виконуваний
    # Check if the script exists and is executable
    if [ -f "$dev_tools_script" ] && [ -x "$dev_tools_script" ]; then
      # Виконуємо скрипт. Права root вже є.
      # Execute the script. Root privileges are already present.
      bash "$dev_tools_script"
      echo "Developer Tools installation step finished."
    else
      # Виводимо помилку, якщо скрипт не знайдено або не має прав
      # Print error if script not found or not executable
      echo "Error: Development tools script ($dev_tools_script) not found or not executable!" >&2
      # Можна зробити це фатальною помилкою / Could make this a fatal error
      # exit 1
    fi
  elif [ "$DEV_TOOLS_ONLY" = false ]; then
      # Повідомлення, якщо dev tools не встановлюються (і це не --dev-only режим)
      # Message if dev tools are not being installed (and not in --dev-only mode)
      echo "--> Skipping developer tools installation (use --dev or --dev-only flag to include)."
  fi

  # --- Завершення ---
  # --- Completion ---
  echo "=============================================================="
  if [ "$DEV_TOOLS_ONLY" = false ]; then
    echo "=== FULL IaC tools installation finished successfully!       ==="
    if [ "$INSTALL_DEV_TOOLS" = true ]; then
      echo "=== (Including requested development tools)              ==="
    fi
  else
    echo "=== DEV-ONLY tools installation finished successfully!       ==="
  fi
  echo "=============================================================="
  echo "Installed:"
  if [ "$DEV_TOOLS_ONLY" = false ]; then
    echo '''  - Dependencies (wget, gpg, curl, lsb-release,
                     apt-transport-https, ca-certificates)'''
    echo "  - Ansible (Verify with: ansible --version)"
    echo "  - OpenTofu (Verify with: tofu --version)"
  fi
  if [ "$INSTALL_DEV_TOOLS" = true ]; then
    echo "  - Development Tools (e.g., shellcheck - Verify with: shellcheck --version)"
  fi
  echo "=============================================================="

  # Знімаємо trap перед нормальним виходом з функції main
  # Remove the trap before normal exit from the main function
  trap - ERR
}

# --- Запуск основної функції ---
# --- Run the main function ---
# Передаємо всі аргументи скрипта ($@) до функції main
# Pass all script arguments ($@) to the main function
main "$@"

# Вихід зі скрипта (код 0 за замовчуванням, якщо main завершилась успішно)
# Exit the script (code 0 by default if main completed successfully)
exit 0
