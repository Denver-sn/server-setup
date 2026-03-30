#!/usr/bin/env bash
# Sécurité de base : fail2ban + SSH hardening
# Le firewall est géré par firewall.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Sécurité du serveur (fail2ban + SSH)"

# ============================================================
# Fail2ban
# ============================================================
log_info "Installation de fail2ban..."
apt_install fail2ban

cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 7200

[sshd-ddos]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 6
findtime = 60
bantime  = 86400

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 3

[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-botsearch]
enabled  = true
port     = http,https
filter   = nginx-botsearch
logpath  = /var/log/nginx/access.log
maxretry = 2
JAIL

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
log_success "Fail2ban configuré (SSH brute force, SSH DDoS, Nginx)"

# ============================================================
# SSH hardening
# ============================================================
log_info "Durcissement SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")

# Vérifier qu'une clé SSH existe avant de désactiver le password auth
if [[ -f "$TARGET_HOME/.ssh/authorized_keys" ]] && [[ -s "$TARGET_HOME/.ssh/authorized_keys" ]]; then
    DISABLE_PASSWORD="yes"
else
    DISABLE_PASSWORD="no"
    log_warn "Aucune clé SSH trouvée pour $TARGET_USER"
    log_warn "PasswordAuthentication reste activé par sécurité"
fi

# Vérifier aussi root
if [[ "$TARGET_USER" != "root" ]] && [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
    ROOT_HAS_KEY="yes"
else
    ROOT_HAS_KEY="no"
fi

cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

# Hardening SSH
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"
sed -i 's/^#\?MaxSessions.*/MaxSessions 3/' "$SSHD_CONFIG"
sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' "$SSHD_CONFIG"
sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSHD_CONFIG"
sed -i 's/^#\?AllowAgentForwarding.*/AllowAgentForwarding no/' "$SSHD_CONFIG"
sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding no/' "$SSHD_CONFIG"
sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSHD_CONFIG"

if [[ "$DISABLE_PASSWORD" == "yes" ]]; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$SSHD_CONFIG"
    log_info "PasswordAuthentication désactivé (clé SSH détectée)"
fi

# Protocoles crypto forts uniquement
if ! grep -q "^KexAlgorithms" "$SSHD_CONFIG"; then
    cat >> "$SSHD_CONFIG" <<'SSH_CRYPTO'

# Crypto hardening
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
SSH_CRYPTO
    log_info "Algorithmes crypto durcis (curve25519, chacha20, ed25519)"
fi

# Valider la config avant de restart
if sshd -t 2>/dev/null; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    log_success "SSH durci et redémarré"
else
    log_error "Config SSH invalide ! Restauration du backup..."
    cp "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    log_warn "sshd_config restauré, aucun changement appliqué"
fi

log_section "Sécurité de base terminée"
echo -e "${GREEN}Résumé :${NC}"
echo "  - Fail2ban : SSH (3 essais/ban 2h), SSH DDoS (6/min/ban 24h), Nginx"
echo "  - SSH : root par clé uniquement, max 3 essais, X11/TCP forward off"
echo "  - Crypto : curve25519, chacha20-poly1305, ed25519"
if [[ "$DISABLE_PASSWORD" == "yes" ]]; then
    echo "  - Password auth : désactivé (clé SSH détectée)"
else
    echo -e "  - ${YELLOW}Password auth : activé (pas de clé SSH trouvée)${NC}"
fi
