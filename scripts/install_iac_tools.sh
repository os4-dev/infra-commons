#!/bin/bash

# Виходити негайно, якщо команда завершується з помилкою
# Exit immediately if a command exits with a non-zero status
set -e

# --- Перевірка запуску від імені root (через sudo) ---
# --- Check if running as root (via sudo) ---
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (using sudo)." >&2
  exit 1
fi

echo "=== Starting IaC tools installation (Ansible, OpenTofu) ==="

# --- Крок 1: Оновлення списку пакетів ---
# --- Step 1: Update apt package lists ---
echo "--> Step 1: Updating apt package lists..."
apt update

# --- Крок 2: Встановлення необхідних залежностей ---
# --- Step 2: Installing necessary dependencies ---
echo "--> Step 2: Installing dependencies (wget, gpg, curl, lsb-release)..."
apt install -y wget gpg curl lsb-release apt-transport-https ca-certificates gnupg

# --- Крок 3: Визначення кодового імені ОС та PPA для Ansible ---
# --- Step 3: Determine OS codename and PPA codename for Ansible ---
echo "--> Step 3: Determining codename for Ansible PPA..."
# Перевірка наявності lsb_release після встановлення
# Verify lsb_release is available after installation
if ! command -v lsb_release &> /dev/null; then
    echo "Error: lsb_release command not found." >&2
    exit 1
fi
# Отримуємо кодове ім'я ОС
# Get OS codename
OS_CODENAME=$(lsb_release -cs)
# Отримуємо ID ОС в нижньому регістрі
# Get OS ID in lowercase
OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

ANSIBLE_PPA_CODENAME=""

echo "Detected OS: $OS_ID, Codename: $OS_CODENAME"

# Визначаємо кодове ім'я PPA для Ansible на основі ОС
# Determine Ansible PPA codename based on OS
if [ "$OS_ID" == "debian" ]; then
  case "$OS_CODENAME" in
    "bookworm") ANSIBLE_PPA_CODENAME="jammy" ;;  # Debian 12 -> Ubuntu 22.04
    "bullseye") ANSIBLE_PPA_CODENAME="focal" ;;  # Debian 11 -> Ubuntu 20.04
    "buster")   ANSIBLE_PPA_CODENAME="bionic" ;; # Debian 10 -> Ubuntu 18.04
    *)
      # Якщо версія Debian невідома, виводимо попередження і пробуємо використати її кодове ім'я
      # If Debian version is unknown, print warning and try using its codename
      echo "Warning: No direct mapping found for Debian '$OS_CODENAME' in Ansible PPA table." >&2
      echo "Attempting to use '$OS_CODENAME' as PPA codename, but this might fail." >&2
      ANSIBLE_PPA_CODENAME="$OS_CODENAME"
      # Можна зробити exit 1, якщо потрібна сувора відповідність
      # Can uncomment exit 1 if strict matching is required
      # exit 1
      ;;
  esac
elif [ "$OS_ID" == "ubuntu" ]; then
  # Для Ubuntu використовуємо його власне кодове ім'я
  # For Ubuntu, use its own codename
  ANSIBLE_PPA_CODENAME="$OS_CODENAME"
  # Тут можна додати перевірки на підтримувані версії Ubuntu, якщо потрібно
  # Can add checks for supported Ubuntu versions here if needed
else
  # Якщо ОС не Debian і не Ubuntu, виходимо з помилкою
  # If OS is not Debian or Ubuntu, exit with error
  echo "Error: Could not determine supported distribution (Debian or Ubuntu required)." >&2
  exit 1
fi

# Переконуємося, що кодове ім'я PPA визначено
# Ensure the PPA codename was determined
if [ -z "$ANSIBLE_PPA_CODENAME" ]; then
    echo "Error: Failed to determine PPA codename for Ansible." >&2
    exit 1
fi

echo "Using PPA codename '$ANSIBLE_PPA_CODENAME' for Ansible."

# --- Крок 4: Виклик скрипта встановлення Ansible ---
# --- Step 4: Call Ansible installation script ---
ANSIBLE_SCRIPT="./install_ansible.sh"
echo "--> Step 4: Running Ansible installation ($ANSIBLE_SCRIPT)..."
# Перевіряємо, чи існує файл скрипта
# Check if the script file exists
if [ -f "$ANSIBLE_SCRIPT" ]; then
  # Надаємо права на виконання (про всяк випадок)
  # Ensure execute permissions (just in case)
  chmod +x "$ANSIBLE_SCRIPT"
  # Викликаємо скрипт, передаючи кодове ім'я PPA
  # Call the script, passing the PPA codename
  "$ANSIBLE_SCRIPT" "$ANSIBLE_PPA_CODENAME"
else
  # Якщо скрипт не знайдено, виходимо з помилкою
  # If script not found, exit with error
  echo "Error: Script $ANSIBLE_SCRIPT not found!" >&2
  exit 1
fi

# --- Крок 5: Виклик скрипта встановлення OpenTofu ---
# --- Step 5: Call OpenTofu installation script ---
OPENTOFU_SCRIPT="./install_opentofu.sh"
echo "--> Step 5: Running OpenTofu installation ($OPENTOFU_SCRIPT)..."
# Перевіряємо, чи існує файл скрипта
# Check if the script file exists
if [ -f "$OPENTOFU_SCRIPT" ]; then
  # Надаємо права на виконання
  # Ensure execute permissions
  chmod +x "$OPENTOFU_SCRIPT"
  # Викликаємо скрипт
  # Call the script
  "$OPENTOFU_SCRIPT"
else
  # Якщо скрипт не знайдено, виходимо з помилкою
  # If script not found, exit with error
  echo "Error: Script $OPENTOFU_SCRIPT not found!" >&2
  exit 1
fi

# --- Завершення ---
# --- Completion ---
echo "=============================================================="
echo "=== IaC tools installation finished!                       ==="
echo "=============================================================="
echo "Installed:"
echo '''  - Dependencies (wget gpg curl lsb-release apt-transport-https
                  ca-certificates gnupg)'''
echo "  - Ansible (Verify with: ansible --version)"
echo "  - OpenTofu (Verify with: tofu --version)"
echo "=============================================================="

exit 0
