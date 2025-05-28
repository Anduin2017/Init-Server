#!/usr/bin/env bash
set -euo pipefail

echo "[+] Updating package index and installing fail2ban..."
sudo apt update
sudo apt install -y fail2ban

echo "[+] Writing /etc/fail2ban/jail.local..."
sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
findtime = 600
bantime  = 3600
EOF
sleep 1

echo "[+] Restarting fail2ban service..."
sudo systemctl restart fail2ban

echo "=== Fail2Ban global status ==="
# Allow script to continue even if fail2ban-client status fails (e.g., socket not yet ready)
sudo fail2ban-client status || true

echo "=== SSHD jail status ==="
sudo fail2ban-client status sshd || true

echo "Tip: To view the currently banned IP list again, run:"
echo "sudo fail2ban-client status sshd"

echo "Tip: To unban an IP address, run:"
echo "sudo fail2ban-client set sshd unbanip <IP_ADDRESS>"

echo "Tip: To ban an IP address manually, run:"
echo "sudo fail2ban-client set sshd banip <IP_ADDRESS>"

echo "Tip: To view the fail2ban logs, run:"
echo "sudo journalctl -u fail2ban"
