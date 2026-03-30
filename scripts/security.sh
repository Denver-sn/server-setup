#!/usr/bin/env bash
# Sécurité : UFW, fail2ban, SSH hardening

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Sécurité du serveur"

# UFW
log_info "Configuration du firewall (UFW)..."
apt_install ufw
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow ssh > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443/tcp > /dev/null
echo "y" | ufw enable > /dev/null
log_success "UFW configuré et activé"

# Fail2ban
log_info "Installation de fail2ban..."
apt_install fail2ban

cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3
JAIL

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
log_success "Fail2ban configuré"

# SSH hardening
log_info "Durcissement SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")

# Vérifier qu'une clé SSH existe avant de désactiver le password auth
if [[ -f "$TARGET_HOME/.ssh/authorized_keys" ]] && [[ -s "$TARGET_HOME/.ssh/authorized_keys" ]]; then
    DISABLE_PASSWORD="yes"
else
    DISABLE_PASSWORD="no"
    log_warn "Aucune clé SSH trouvée pour $TARGET_USER dans $TARGET_HOME/.ssh/authorized_keys"
    log_warn "PasswordAuthentication reste activé par sécurité"
fi

cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"
sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' "$SSHD_CONFIG"
sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSHD_CONFIG"

if [[ "$DISABLE_PASSWORD" == "yes" ]]; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    log_info "PasswordAuthentication désactivé (clé SSH détectée)"
fi

# Valider la config avant de restart
if sshd -t 2>/dev/null; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    log_success "SSH durci et redémarré"
else
    log_error "Config SSH invalide ! Restauration du backup..."
    cp "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
    log_warn "sshd_config restauré, aucun changement appliqué"
fi
