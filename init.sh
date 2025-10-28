#!/bin/bash
set -euo pipefail
export LC_ALL=C
export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

#==========================
# Color
#==========================
export Green="\033[32m"
export Red="\033[31m"
export Yellow="\033[33m"
export Blue="\033[36m"
export Font="\033[0m"
export GreenBG="\033[42;37m"
export RedBG="\033[41;37m"
export INFO="${Blue}[ INFO ]${Font}"
export OK="${Green}[  OK  ]${Font}"
export ERROR="${Red}[FAILED]${Font}"
export WARNING="${Yellow}[ WARN ]${Font}"

#==========================
# Print Colorful Text
#==========================
function print_ok() {
  echo -e "${OK} ${Blue} $1 ${Font}"
}

function print_info() {
  echo -e "${INFO} ${Font} $1"
}

function print_error() {
  echo -e "${ERROR} ${Red} $1 ${Font}"
}

function print_warn() {
  echo -e "${WARNING} ${Yellow} $1 ${Font}"
}

#===============================================================================
# Concise server preparation script with error confirmation (idempotent)
#===============================================================================

#-----------------------------------
# Error handling & confirmation
#-----------------------------------
on_error(){ print_error "Error at line $1."; areYouSure; }
trap 'on_error $LINENO' ERR

areYouSure(){
  print_warn "Continue despite errors? [y/N]"
  read -r ans
  case $ans in [yY]*) print_ok "Continuing...";; *) print_error "Aborted."; exit 1;; esac
}

#-----------------------------------
# Helpers
#-----------------------------------
run_local(){   print_ok "Local: $*"; "$@"; }
run_remote(){  sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$SERVER" "$*"; }
wait_ssh(){
  print_ok "Waiting for SSH on $SERVER... (Running ssh $REMOTE_USER@$SERVER)"
  until sshpass -p "$REMOTE_PASS" ssh -q \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=5 \
      "$REMOTE_USER@$SERVER" exit; do
    print_warn "SSH not ready, retrying in 5s..."
    sleep 5
  done
  print_ok "SSH available."
}

usage(){ echo "Usage: $0 <orig_user> <orig_pass> <server> <new_hostname> <new_user>"; exit 1; }

#-----------------------------------
# Main
#-----------------------------------
[ $# -ne 5 ] && usage
USER="$1"; PASS="$2"; SERVER="$3"; HOSTNAME="$4"; NEWUSER="$5"
REMOTE_USER="$USER"; REMOTE_PASS="$PASS"

# 1) Install sshpass locally
run_local sudo apt-get update -y
run_local sudo apt-get install -y sshpass

# 2) Clear known_hosts, wait for SSH
run_local ssh-keygen -R "$SERVER" -f ~/.ssh/known_hosts
wait_ssh

# 3) Hostname & reboot (only if changed)
CURRENT_HOST=$(run_remote "hostname")
if [[ "$CURRENT_HOST" != "$HOSTNAME" ]]; then
  print_ok "Setting hostname to $HOSTNAME"
  run_remote "sudo hostnamectl set-hostname $HOSTNAME"
  run_remote "sudo reboot" || true
  print_ok "Server rebooting..."
  sleep 5
  wait_ssh
else
  print_ok "Hostname already '$HOSTNAME', skipping"
fi

# 4) Create or verify new user
if run_remote "id -u $NEWUSER" &>/dev/null; then
  print_ok "User $NEWUSER exists"
else
  print_ok "Creating user $NEWUSER"
  run_remote "sudo adduser --disabled-password --gecos '' $NEWUSER"
fi

# 5) Grant sudo & set up passwordless
print_ok "Granting sudo to $NEWUSER"
run_remote "sudo usermod -aG sudo $NEWUSER"
print_ok "Setting passwordless sudo for $NEWUSER"
run_remote "echo '$NEWUSER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$NEWUSER"

# # 6) Generate & persist random password (once)
# if run_remote "[ -f /etc/$NEWUSER.pass ]" &>/dev/null; then
#   # Test if this password is correct.
#   PASS_IN_PLACE=$(run_remote "sudo cat /etc/$NEWUSER.pass")
#   print_ok "Password for $NEWUSER already exists, testing validity..."
#   if run_remote "echo '$NEWUSER:$PASS_IN_PLACE' | sudo chpasswd" &>/dev/null; then
#     # If the password is correct, we can reuse it.
#     print_ok "Password for $NEWUSER is already set and valid. Reusing existing password."
#     PASS_NEW=$(run_remote "sudo cat /etc/$NEWUSER.pass")
#   else
#     # If the password is not correct, we need to generate a new one.
#     print_warn "Password for $NEWUSER is not valid. Generating a new password."
#     run_remote "sudo rm -f /etc/$NEWUSER.pass"
#     PASS_NEW=$(uuidgen)
#     print_ok "Setting new password for $NEWUSER"
#     run_remote "echo '$NEWUSER:$PASS_NEW' | sudo chpasswd"
#     run_remote "echo '$PASS_NEW' | sudo tee /etc/$NEWUSER.pass > /dev/null"
#     run_remote "sudo chmod 600 /etc/$NEWUSER.pass"
#     run_remote "sudo chown root:root /etc/$NEWUSER.pass"
#     print_ok "New password generated for $NEWUSER and persisted at /etc/$NEWUSER.pass. Please back it up! It can still be used to log in via serial console or rescue mode!"
#   fi
# else
#   PASS_NEW=$(uuidgen)
#   print_ok "Setting password for $NEWUSER"
#   run_remote "echo '$NEWUSER:$PASS_NEW' | sudo chpasswd"
#   run_remote "echo '$PASS_NEW' | sudo tee /etc/$NEWUSER.pass > /dev/null"
#   run_remote "sudo chmod 600 /etc/$NEWUSER.pass"
#   run_remote "sudo chown root:root /etc/$NEWUSER.pass"
#   print_ok "New password generated for $NEWUSER and persisted at /etc/$NEWUSER.pass. Please back it up! It can still be used to log in via serial console or rescue mode!"
# fi

# 6) Generate & persist random password (once)

# 6.1) Read or generate password candidate.
PASS_FILE="/etc/$NEWUSER.pass"
if run_remote "[ -f $PASS_FILE ]" &>/dev/null; then
  print_ok "Password file $PASS_FILE exists, reading existing password."
  PASS_CANDIDATE=$(run_remote "sudo cat $PASS_FILE")
else
  print_ok "Password file $PASS_FILE does not exist, generating a new password."
  PASS_CANDIDATE=$(uuidgen)
fi

# 6.2) Test if the password candidate is valid. If failed, regenerate.
if ! run_remote "echo '$NEWUSER:$PASS_CANDIDATE' | sudo chpasswd" &>/dev/null; then
  print_warn "The old password $PASS_CANDIDATE is not valid for user $NEWUSER. Generating a new password."
  run_remote "sudo rm -f $PASS_FILE" 2>/dev/null || true
  PASS_CANDIDATE=$(uuidgen)
else
  print_ok "Password candidate $PASS_CANDIDATE is valid for user $NEWUSER."
fi

# 6.3) Set the new password and persist it.
print_ok "Setting password for $NEWUSER"
PASS_NEW="$PASS_CANDIDATE"
run_remote "echo '$NEWUSER:$PASS_CANDIDATE' | sudo chpasswd"
run_remote "echo '$PASS_CANDIDATE' | sudo tee $PASS_FILE > /dev/null"
run_remote "sudo chmod 600 $PASS_FILE"
run_remote "sudo chown root:root $PASS_FILE"
print_ok "New password generated for $NEWUSER and persisted at $PASS_FILE. Please back it up! It can still be used to log in via serial console or rescue mode!"

# 6.4) Save the password locally for convenience.
local_pass_file="./password_${NEWUSER}_at_${SERVER}.txt"
rm -f "$local_pass_file" 2>/dev/null || true
sshpass -p "$REMOTE_PASS" ssh -q -o StrictHostKeyChecking=no \
  "$REMOTE_USER@$SERVER" "sudo cat /etc/$NEWUSER.pass" \
  > "$local_pass_file"
sudo chown "$USER:$USER" "$local_pass_file"
sudo chmod 600 "$local_pass_file"
print_ok "Password for $NEWUSER saved locally at $local_pass_file [DO NOT SHARE THIS FILE! IT CAN BE USED TO LOG IN VIA SERIAL CONSOLE OR RESCUE MODE!]"

# 7) Copy SSH key (only if absent)
[ ! -f ~/.ssh/id_rsa.pub ] && run_local ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
PUBKEY=$(<~/.ssh/id_rsa.pub)
print_ok "Ensuring SSH key in authorized_keys"
run_remote "mkdir -p /home/$NEWUSER/.ssh && \
  sudo bash -c 'grep -qxF \"$PUBKEY\" /home/$NEWUSER/.ssh/authorized_keys 2>/dev/null || \
  echo \"$PUBKEY\" >> /home/$NEWUSER/.ssh/authorized_keys' && \
  sudo chown -R $NEWUSER:$NEWUSER /home/$NEWUSER/.ssh && \
  sudo chmod 700 /home/$NEWUSER/.ssh && \
  sudo chmod 600 /home/$NEWUSER/.ssh/authorized_keys"

# Switch to new user for subsequent operations
print_ok "Switching to new user $NEWUSER"
REMOTE_USER="$NEWUSER"; REMOTE_PASS="$PASS_NEW"
wait_ssh

# 8) Harden SSH
print_ok "Hardening SSH settings"
run_remote "sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/; \
  s/PasswordAuthentication yes/PasswordAuthentication no/; \
  s/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
  sudo systemctl restart sshd || sudo systemctl restart ssh"

# 9) Remove other non-system users
print_ok "Removing other users"
others=$(run_remote "awk -F: -v skip='$NEWUSER' '\$3>=1000 && \$1!=skip && \$1!=\"nobody\" && \$1!=\"nogroup\" {print \$1}' /etc/passwd")

for u in $others; do
  print_warn "Deleting user $u"
  run_remote "sudo pkill -u $u || true; sudo deluser --remove-home $u"
done

# 10) Reset machine-id
print_ok "Resetting machine-id"
run_remote "sudo rm -f /etc/machine-id /var/lib/dbus/machine-id && \
  sudo systemd-machine-id-setup && \
  sudo cp /etc/machine-id /var/lib/dbus/machine-id"

# 11) Enable UFW & OpenSSH
print_ok "Enabling UFW firewall"
run_remote "sudo apt-get install -y ufw && sudo ufw allow OpenSSH && echo y | sudo ufw enable"

# 12) Install & configure Fail2Ban
print_ok "Installing Fail2Ban"
run_remote "sudo apt-get update && sudo apt-get install -y fail2ban"
print_ok "Configuring Fail2Ban"
run_remote <<'EOF'
sudo tee /etc/fail2ban/jail.local > /dev/null <<EOJ
[sshd]
enabled   = true
port      = ssh
filter    = sshd
backend  = systemd
logpath  = journal
maxretry  = 3
findtime  = 600
bantime   = 3600
EOJ
sudo systemctl restart fail2ban
EOF
print_ok "Fail2Ban setup complete"

# 13) Enable BBR (only once)
print_ok "Enabling BBR congestion control"
run_remote <<'EOF'
grep -q 'net.ipv4.tcp_congestion_control = bbr' /etc/sysctl.d/99-bbr.conf 2>/dev/null || {
  sudo tee /etc/sysctl.d/99-bbr.conf > /dev/null <<SYSCTL
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL
  sudo sysctl --system
}
EOF

# 14) Select best mirror & update
print_ok "Selecting best mirror & updating"
run_remote "curl -s https://gitlab.aiursoft.com/anduin/init-server/-/raw/master/mirror.sh?ref_type=heads | bash"
run_remote "sudo apt-get update"

# 15) Install clean traffic
print_ok "Installing clean traffic"
run_remote "curl -sL https://gitlab.aiursoft.com/anduin/clean-traffic/-/raw/master/install.sh | sudo bash"

# 16) Install or upgrade latest HWE kernel if needed
print_ok "Checking HWE kernel package on remote"
run_remote <<'EOF'
set -euo pipefail

# Try to find the HWE package
HWE_PKG=$(apt search linux-generic-hwe- 2>/dev/null | grep -o 'linux-generic-hwe-[^/ ]*' | head -1)

if [ -z "$HWE_PKG" ]; then
  echo "[  OK  ] No HWE kernel package found for this release, skipping"
else
  inst=$(apt-cache policy "$HWE_PKG" | awk '/Installed:/ {print $2}')
  cand=$(apt-cache policy "$HWE_PKG" | awk '/Candidate:/ {print $2}')

  if dpkg -s "$HWE_PKG" &>/dev/null; then
    if [ "$inst" != "$cand" ] && [ "$cand" != "(none)" ]; then
      echo "[  OK  ] Upgrading $HWE_PKG from $inst to $cand"
      sudo apt-get update
      sudo apt-get install -y "$HWE_PKG"
      echo reboot_required > /tmp/.reboot_flag
    else
      echo "[  OK  ] $HWE_PKG is already at latest version ($inst), skipping"
    fi
  else
    if [ "$cand" != "(none)" ]; then
      echo "[  OK  ] Installing $HWE_PKG ($cand)"
      sudo apt-get update
      sudo apt-get install -y "$HWE_PKG"
      echo reboot_required > /tmp/.reboot_flag
    else
      echo "[  OK  ] $HWE_PKG has no installation candidate, skipping"
    fi
  fi
fi
EOF

# 17) Conditionally reboot & wait
if run_remote 'test -f /tmp/.reboot_flag'; then
  print_ok "Rebooting server to apply new kernel"
  run_remote "rm -f /tmp/.reboot_flag"
  run_remote "sudo reboot" || true
  sleep 5
  wait_ssh
else
  print_ok "No new kernel installed, skipping reboot"
fi

# 18) Final updates & cleanup
print_ok "Installing upgrades & cleanup"
run_remote "sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y"

# 19) Performance tuning
print_ok "Tuning CPU performance & timezone"
run_remote "sudo apt-get install -y linux-tools-$(uname -r) cpupower && \
  sudo cpupower frequency-set -g performance || true && \
  sudo timedatectl set-timezone GMT"

# 20) Remove snap
print_ok "Removing snapd"
run_remote <<'EOF'
# 1) 如果 snapd.service 存在，就 disable 一下；否则跳过
if systemctl list-unit-files | grep -q '^snapd\.service'; then
  sudo systemctl disable --now snapd || true
else
  echo "[  OK  ] snapd.service not found, skipping disable"
fi

# 2) 如果 dpkg 里检测到 snapd 包，就 purge 并清理数据目录
if dpkg -l snapd &>/dev/null; then
  sudo apt-get purge -y snapd
  sudo rm -rf /snap /var/lib/snapd /var/cache/snapd
else
  echo "[  OK  ] snapd package not installed, skipping purge"
fi

# 3) 在所有机器都写上 no-snap 的 pin
sudo tee /etc/apt/preferences.d/no-snap.pref > /dev/null <<EOP
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOP
EOF

# 21) Final cleanup & benchmark
print_ok "Final autoremove & benchmark"
run_remote "sudo apt-get autoremove -y --purge && \
  sudo apt-get install -y sysbench stun-client && sysbench cpu --threads=$(nproc) run && \
  sudo apt-get autoremove -y sysbench --purge"

#stun stun.l.google.com:19302
print_ok "Testing STUN connectivity"
run_remote "stun stun.l.google.com:19302" || true

print_ok "Setup complete. Connect via: ssh $NEWUSER@$SERVER"

# After this script, server will:

