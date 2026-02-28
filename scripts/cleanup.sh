#!/bin/bash
# =============================================================
# AWS Marketplace cleanup script
# Запускается последним шагом перед созданием snapshot
# =============================================================

set -e

echo "=== Starting AWS Marketplace cleanup ==="

# ── Пакеты и кэш ─────────────────────────────────────────────
echo "--- Cleaning apt cache..."
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# ── Credentials и ключи ──────────────────────────────────────
echo "--- Removing credentials..."
rm -f /home/ubuntu/.ssh/authorized_keys
rm -f /root/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*                    # будут regenerated при первом старте
rm -rf /home/ubuntu/.aws
rm -rf /root/.aws
find / -name "*.pem" -not -path "/etc/ssl/*" -delete 2>/dev/null || true
find / -name "*.key" -not -path "/etc/ssl/*" -not -path "/etc/nginx/*" -delete 2>/dev/null || true

# ── История команд ───────────────────────────────────────────
echo "--- Clearing shell history..."
rm -f /root/.bash_history
rm -f /home/ubuntu/.bash_history
unset HISTFILE

# ── Логи ─────────────────────────────────────────────────────
echo "--- Clearing logs..."
find /var/log -type f | while read f; do
  truncate -s 0 "$f" 2>/dev/null || true
done
rm -rf /var/log/journal/*

# ── Временные файлы ──────────────────────────────────────────
echo "--- Clearing temp files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# ── Cloud-init: сбрасываем состояние ─────────────────────────
# При следующем запуске cloud-init выполнится заново:
# - установит SSH ключ пользователя
# - настроит hostname
# - выполнит user-data скрипты
echo "--- Resetting cloud-init..."
cloud-init clean --logs --seed

# ── Machine ID — должен быть уникальным для каждого инстанса ─
echo "--- Resetting machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# ── Network ──────────────────────────────────────────────────
echo "--- Cleaning network artifacts..."
rm -f /etc/netplan/50-cloud-init.yaml   # cloud-init пересоздаст
rm -rf /var/lib/dhcp/*

# ── Пользовательские данные ──────────────────────────────────
echo "--- Removing build artifacts..."
rm -rf /home/ubuntu/.ansible
rm -rf /root/.ansible

echo "=== Cleanup complete. AMI is ready for marketplace ==="
