#!/bin/bash

# Виходити негайно, якщо команда завершується з помилкою
# Exit immediately if a command exits with a non-zero status
set -e

# --- Початок блоку обробки помилок ---
# --- Start of error handling block ---
# (Залишається без змін / Remains unchanged)
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

# === Функції / Functions ===

# Перевірка запуску від імені root
# Check if running as root
check_root() {
  echo "--> Verifying root privileges..."
  if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root (using sudo)." >&2
    exit 1
  fi
  echo "Root privileges verified."
}

# Оновлення пакетів та встановлення залежностей
# Update packages and install dependencies
prepare_system() {
  echo "--> Step 1 & 2: Updating package list and installing dependencies..."
  # Оновлення / Update
  apt-get update

  # Встановлення залежностей / Install dependencies
  apt-get install -y wget gpg curl lsb-release apt-transport-https ca-certificates
  echo "System preparation complete (update & dependencies installed)."
}

# Визначення кодового імені та встановлення Ansible
# Determine codename and install Ansible
install_ansible() {
  local ansible_script="./install_ansible.sh" # Шлях до скрипта / Path to the script
  local ansible_ppa_codename=""             # Локальна змінна для цієї функції / Local variable for this function

  echo "--> Step 3 & 4: Determining codename and installing Ansible..."
  # --- Визначення кодового імені PPA для Ansible ---
  # --- Determine PPA codename for Ansible ---
  echo "Determining OS details for Ansible PPA..."
  if ! command -v lsb_release &> /dev/null; then
      echo "Error: lsb_release command not found." >&2
      exit 1
  fi
  local os_codename
  local os_id
  os_codename=$(lsb_release -cs)
  os_id=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

  echo "Detected OS: $os_id, Codename: $os_codename"

  if [ "$os_id" == "debian" ]; then
    case "$os_codename" in
      "bookworm") ansible_ppa_codename="jammy" ;;
      "bullseye") ansible_ppa_codename="focal" ;;
      "buster")   ansible_ppa_codename="bionic" ;;
      *)
        echo "Warning: No direct mapping found for Debian '$os_codename'. Using '$os_codename' itself." >&2
        ansible_ppa_codename="$os_codename"
        ;;
    esac
  elif [ "$os_id" == "ubuntu" ]; then
    ansible_ppa_codename="$os_codename"
  else
    echo "Error: Could not determine supported distribution (Debian or Ubuntu required)." >&2
    exit 1
  fi

  if [ -z "$ansible_ppa_codename" ]; then
      echo "Error: Failed to determine PPA codename for Ansible." >&2
      exit 1
  fi
  echo "Using PPA codename '$ansible_ppa_codename' for Ansible."

  # --- Запуск встановлення Ansible ---
  # --- Run Ansible installation ---
  echo "Running Ansible installation script ($ansible_script)..."
  if [ -f "$ansible_script" ]; then
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
  local opentofu_script="./install_opentofu.sh" # Шлях до скрипта / Path to the script
  echo "--> Step 5: Running OpenTofu installation ($opentofu_script)..."
  if [ -f "$opentofu_script" ]; then
    chmod +x "$opentofu_script"
    # Викликаємо скрипт OpenTofu
    # Call the OpenTofu script
    "$opentofu_script"
  else
    echo "Error: Script $opentofu_script not found!" >&2
    exit 1
  fi
  echo "OpenTofu installation step finished."
}

# === Основна логіка / Main Logic ===
main() {
  echo "=== Starting IaC tools installation (Ansible, OpenTofu) ==="

  # Виклик функцій покроково / Call functions step-by-step
  check_root
  prepare_system    # Включає update та install deps / Includes update and install deps
  install_ansible   # Включає визначення кодового імені та запуск інсталятора / Includes codename detection and installer run
  install_opentofu  # Встановлення OpenTofu / Installs OpenTofu

  # --- Завершення ---
  # --- Completion ---
  echo "=============================================================="
  echo "=== IaC tools installation finished successfully!          ==="
  echo "=============================================================="
  echo "Installed:"
  echo '''  - Dependencies (wget, gpg, curl, lsb-release, 
                   apt-transport-https, ca-certificates)'''
  echo "  - Ansible (Verify with: ansible --version)"
  echo "  - OpenTofu (Verify with: tofu --version)"
  echo "=============================================================="

  # Знімаємо trap перед нормальним виходом з функції main
  # Remove the trap before normal exit from the main function
  trap - ERR
}

# --- Запуск основної функції ---
# --- Run the main function ---
main

# Вихід зі скрипта (код 0 за замовчуванням, якщо main завершилась успішно)
# Exit the script (code 0 by default if main completed successfully)
exit 0
