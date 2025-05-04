#!/bin/bash

# Виходити негайно, якщо команда завершується з помилкою
# Exit immediately if a command exits with a non-zero status
set -e

# Перевірка наявності аргументу (кодового імені Ubuntu PPA)
# Check if the Ubuntu PPA codename argument is provided
if [ -z "$1" ]; then
  echo "[Ansible] Error: Ubuntu PPA codename argument is required." >&2
  exit 1
fi

UBUNTU_CODENAME="$1"
KEY_URL="https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367"
KEY_DEST="/usr/share/keyrings/ansible-archive-keyring.gpg"
REPO_FILE="/etc/apt/sources.list.d/ansible.list"

echo "[Ansible] Installing for Ubuntu PPA '$UBUNTU_CODENAME'..."

# --- Крок 1: Завантаження та встановлення GPG ключа Ansible PPA ---
# --- Step 1: Download and install the Ansible PPA GPG key ---
echo "[Ansible] Downloading GPG key..."
# Видаляємо старий ключ, якщо існує, щоб уникнути конфліктів
# Remove the old key if it exists to avoid conflicts
rm -f "$KEY_DEST"
# Завантажуємо та зберігаємо ключ
# Download and save the key
wget -qO- "$KEY_URL" | gpg --dearmour -o "$KEY_DEST"
# Перевірка створення ключа
# Verify key creation
if [ ! -f "$KEY_DEST" ]; then
    echo "[Ansible] Error: Failed to create GPG key file $KEY_DEST" >&2
    exit 1
fi
# Встановлюємо коректні права
# Set correct permissions
chmod 644 "$KEY_DEST"
echo "[Ansible] GPG key saved to $KEY_DEST"

# --- Крок 2: Додавання репозиторію Ansible PPA ---
# --- Step 2: Add the Ansible PPA repository ---
echo "[Ansible] Adding PPA repository..."
# Формування рядка репозиторію
# Format the repository line
REPO_LINE="deb [signed-by=$KEY_DEST] http://ppa.launchpad.net/ansible/ansible/ubuntu $UBUNTU_CODENAME main"
# Запис у файл репозиторію
# Write to the repository file
echo "$REPO_LINE" | tee "$REPO_FILE" > /dev/null
# Перевірка створення файлу репозиторію
# Verify repository file creation
if ! grep -F -q "$REPO_LINE" "$REPO_FILE"; then
     echo "[Ansible] Error: Failed to add repository to $REPO_FILE" >&2
     # Видаляємо ключ, якщо репо не додано
     # Remove the key if repo addition failed
     rm -f "$KEY_DEST"
     exit 1
fi
echo "[Ansible] Repository added to $REPO_FILE"

# --- Крок 3: Встановлення Ansible ---
# --- Step 3: Install Ansible ---
# apt update виконується в головному скрипті ПЕРЕД викликом цього
# apt update is run in the main script BEFORE calling this one
echo "[Ansible] Installing 'ansible' package..."
apt install -y ansible

echo "[Ansible] Ansible installation completed successfully."
exit 0
