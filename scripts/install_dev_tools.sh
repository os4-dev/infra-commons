#!/bin/bash

# ===-----------------------------------------------------------------------===
# Script to install common development tools
# Скрипт для встановлення поширених інструментів розробки
# ===-----------------------------------------------------------------------===

# Виходити негайно, якщо команда завершується з помилкою
# Exit immediately if a command exits with a non-zero status
set -e

# Функція для виводу інформаційних повідомлень
# Function to print informational messages
log() {
  echo "[DevTools] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- Функції Встановлення / Installation Functions ---

# Встановлення shellcheck
# Install shellcheck
install_shellcheck() {
  log "Checking and installing shellcheck..."
  # Перевіряємо, чи команда існує / Check if command exists
  if ! command -v shellcheck > /dev/null 2>&1; then
    # Припускаємо систему на базі apt (Debian/Ubuntu/Proxmox)
    # Assuming apt-based system (Debian/Ubuntu/Proxmox)
    apt-get install -y shellcheck
    log "shellcheck installed successfully."
  else
    log "shellcheck is already installed."
  fi
}

# Тут можна додати функції для інших інструментів розробки
# Add functions for other dev tools here later
# install_jq() { ... }
# install_yq() { ... }

# --- Основна Логіка / Main Logic ---

log "Starting Developer Tools Installation..."

# Оновити список пакетів один раз перед встановленням
# Update package list once before installing
log "Updating package list (required for dev tools installation)..."
apt-get update

# Виклик функцій встановлення / Call installation functions
install_shellcheck
# install_jq
# install_yq

log "Developer Tools Installation finished."

exit 0
