#!/usr/bin/env bash
# Sécurité de base : changement port SSH + fail2ban + SSH hardening
# Le firewall est géré par firewall.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Sécurité du serveur"

SSHD_CONFIG="/etc/ssh/sshd_config"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")
SSH_PORT=22

# ============================================================
# 1. Changement de port SSH
# ============================================================
change_ssh_port() {
    log_info "Port SSH actuel : 22"

    if confirm "  Changer le port SSH (recommandé) ?"; then
        read -r -p "  > Nouveau port SSH (ex: 2222, 2200, 4922) : " NEW_PORT < /dev/tty

        if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || (( NEW_PORT < 1024 || NEW_PORT > 65535 )); then
            log_warn "Port invalide ($NEW_PORT). Doit être entre 1024 et 65535. On reste sur 22."
            return
        fi

        if ss -tlnp | grep -q ":${NEW_PORT} " 2>/dev/null; then
            log_warn "Port $NEW_PORT déjà utilisé. On reste sur 22."
            return
        fi

        SSH_PORT="$NEW_PORT"
        log_success "Port SSH sera changé : 22 -> $SSH_PORT"
    else
        log_info "Port SSH inchangé (22)"
    fi
}

# Mode non-interactif via variable d'env
if [[ -n "${SSH_CUSTOM_PORT:-}" ]]; then
    SSH_PORT="$SSH_CUSTOM_PORT"
    log_info "Port SSH défini via env : $SSH_PORT"
else
    change_ssh_port
fi

# Sauvegarder le port pour les autres scripts (firewall.sh, etc.)
echo "$SSH_PORT" > /etc/server-setup-ssh-port

# ============================================================
# 2. Appliquer le port dans sshd_config
# ============================================================
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

if (( SSH_PORT != 22 )); then
    if grep -q "^#\?Port " "$SSHD_CONFIG"; then
        sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
    else
        sed -i "1a Port ${SSH_PORT}" "$SSHD_CONFIG"
    fi

    # Ouvrir le nouveau port dans UFW AVANT de toucher au reste
    if is_installed ufw; then
        ufw allow "${SSH_PORT}/tcp" comment "SSH custom" > /dev/null 2>&1
        log_info "Port $SSH_PORT ouvert dans UFW"
    fi

    log_success "sshd_config : Port $SSH_PORT"
fi

# ============================================================
# 3. SSH hardening
# ============================================================
log_info "Durcissement SSH..."

# Vérifier les clés SSH avant de désactiver password auth
if [[ -f "$TARGET_HOME/.ssh/authorized_keys" ]] && [[ -s "$TARGET_HOME/.ssh/authorized_keys" ]]; then
    DISABLE_PASSWORD="yes"
elif [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
    DISABLE_PASSWORD="yes"
else
    DISABLE_PASSWORD="no"
    log_warn "Aucune clé SSH trouvée pour $TARGET_USER"
    log_warn "PasswordAuthentication reste activé par sécurité"
fi

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

# Crypto hardening
if ! grep -q "^KexAlgorithms" "$SSHD_CONFIG"; then
    cat >> "$SSHD_CONFIG" <<'SSH_CRYPTO'

# Crypto hardening
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
SSH_CRYPTO
    log_info "Crypto durci (curve25519, chacha20, ed25519)"
fi

# Valider et appliquer
if sshd -t 2>/dev/null; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    log_success "SSH durci et redémarré sur port $SSH_PORT"
else
    log_error "Config SSH invalide ! Restauration du backup..."
    cp "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    log_warn "sshd_config restauré, aucun changement appliqué"
fi

# Fermer le port 22 dans UFW si on a changé de port
if (( SSH_PORT != 22 )) && is_installed ufw; then
    ufw delete allow ssh > /dev/null 2>&1 || true
    ufw delete allow 22/tcp > /dev/null 2>&1 || true
    log_info "Port 22 fermé dans UFW"
fi

# ============================================================
# 4. Fail2ban (après changement de port)
# ============================================================
log_info "Installation de fail2ban..."
apt_install fail2ban

cat > /etc/fail2ban/jail.local <<JAIL
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 7200

[sshd-ddos]
enabled  = true
port     = ${SSH_PORT}
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
log_success "Fail2ban configuré sur port $SSH_PORT"

# ============================================================
# Résumé
# ============================================================
log_section "Sécurité de base terminée"
echo -e "${GREEN}Résumé :${NC}"
echo "  - Port SSH : $SSH_PORT"
echo "  - Fail2ban : SSH (3 essais/ban 2h), DDoS (6/min/ban 24h), Nginx"
echo "  - SSH : root par clé uniquement, max 3 essais, X11/TCP forward off"
echo "  - Crypto : curve25519, chacha20-poly1305, ed25519"
if [[ "$DISABLE_PASSWORD" == "yes" ]]; then
    echo "  - Password auth : désactivé"
else
    echo -e "  - ${YELLOW}Password auth : activé (pas de clé SSH trouvée)${NC}"
fi
if (( SSH_PORT != 22 )); then
    echo ""
    echo -e "${YELLOW}  IMPORTANT : Reconnecte-toi avec : ssh -p $SSH_PORT user@ip${NC}"
fi
