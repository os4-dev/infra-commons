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
  echo "[OpenTofu] ERROR: Script failed on line $line_num with exit code $exit_code." >&2
  echo "[OpenTofu] Failing command: $command" >&2
  echo "------------------------------------------------------------" >&2
}
trap 'handle_error $LINENO' ERR
# --- Кінець блоку обробки помилок ---
# --- End of error handling block ---

# Визначення шляхів до ключів та файлу репозиторію
# Define paths for keys and repository file
KEYRING_DIR="/etc/apt/keyrings"
KEY_1_PATH="${KEYRING_DIR}/opentofu.gpg"
KEY_2_PATH="${KEYRING_DIR}/opentofu-repo.gpg"
REPO_FILE="/etc/apt/sources.list.d/opentofu.list"

echo "[OpenTofu] Starting installation based on updated instructions..."

# --- Крок 1: Створення директорії для ключів APT ---
# --- Step 1: Create directory for APT keyrings ---
echo "[OpenTofu] Ensuring keyring directory exists: ${KEYRING_DIR}"
# Використовуємо install для створення директорії з правильними правами
# Use install to create the directory with correct permissions
install -m 0755 -d "$KEYRING_DIR"

# --- Крок 2: Завантаження та встановлення GPG ключів OpenTofu ---
# --- Step 2: Download and install OpenTofu GPG keys ---
echo "[OpenTofu] Downloading GPG keys..."
# Видаляємо старі ключі, якщо існують
# Remove old keys if they exist
rm -f "$KEY_1_PATH" "$KEY_2_PATH"

# Завантажуємо перший ключ (бінарний?)
# Download the first key (binary?)
curl -fsSL https://get.opentofu.org/opentofu.gpg | tee "$KEY_1_PATH" > /dev/null
# Завантажуємо та деарморизуємо другий ключ (ASCII-armored)
# Download and dearmor the second key (ASCII-armored)
curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | gpg --no-tty --batch --dearmor -o "$KEY_2_PATH" > /dev/null

# Перевірка створення ключів
# Verify key creation
if [ ! -f "$KEY_1_PATH" ] || [ ! -f "$KEY_2_PATH" ]; then
    echo "[OpenTofu] Error: Failed to create one or both GPG key files ($KEY_1_PATH, $KEY_2_PATH)" >&2
    exit 1
fi

# Встановлюємо права доступу для читання всім
# Set read permissions for all users
chmod a+r "$KEY_1_PATH" "$KEY_2_PATH"
echo "[OpenTofu] GPG keys saved and permissions set in $KEYRING_DIR"

# --- Крок 3: Створення файлу репозиторію OpenTofu ---
# --- Step 3: Create the OpenTofu repository source list file ---
echo "[OpenTofu] Creating repository source list file: $REPO_FILE"
# Видаляємо старий файл репозиторію, якщо існує
# Remove old repository file if it exists
rm -f "$REPO_FILE"

# Створюємо новий файл з рядками deb та deb-src, підписаними обома ключами
# Create the new file with deb and deb-src lines, signed by both keys
echo "deb [signed-by=${KEY_1_PATH},${KEY_2_PATH}] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=${KEY_1_PATH},${KEY_2_PATH}] https://packages.opentofu.org/opentofu/tofu/any/ any main" | tee "$REPO_FILE" > /dev/null

# Перевірка створення файлу репозиторію
# Verify repository file creation
if ! grep -q "packages.opentofu.org/opentofu/tofu" "$REPO_FILE"; then
     echo "[OpenTofu] Error: Failed to add repository information to $REPO_FILE" >&2
     # Видаляємо ключі, якщо репо не додано
     # Remove keys if repo addition failed
     rm -f "$KEY_1_PATH" "$KEY_2_PATH"
     exit 1
fi

# Встановлюємо права доступу для читання всім
# Set read permissions for all users
chmod a+r "$REPO_FILE"
echo "[OpenTofu] Repository source list created at $REPO_FILE"

# --- Крок 4: Оновлення списку пакетів та встановлення OpenTofu ---
# --- Step 4: Update package list and install OpenTofu ---
# apt update потрібно виконати ПІСЛЯ додавання нового репозиторію
# apt update needs to be run AFTER adding the new repository
echo "[OpenTofu] Updating apt package list..."
apt-get update # Використовуємо apt-get, як в інструкції / Using apt-get as per instructions

echo "[OpenTofu] Installing 'tofu' package..."
# Пакет називається 'tofu'
# The package name is 'tofu'
apt-get install -y tofu

echo "[OpenTofu] OpenTofu installation completed successfully."
# Знімаємо trap перед нормальним виходом
# Remove the trap before normal exit
trap - ERR
exit 0
