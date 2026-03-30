#!/usr/bin/env bash
# Hardening VPS avancé
# - Unattended-upgrades (patchs auto)
# - Sysctl hardening (réseau/kernel)
# - Création user sudo
# - Swap
# - Shared memory
# - Disable services inutiles
# - Audit logs
# - Bannière SSH
# - Restrictions cron

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Hardening VPS"

TARGET_USER="${SUDO_USER:-$USER}"

# ============================================================
# 1. Unattended-upgrades (mises à jour de sécurité automatiques)
# ============================================================
setup_unattended_upgrades() {
    log_info "Configuration des mises à jour automatiques..."
    apt_install unattended-upgrades apt-listchanges

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'CONF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
CONF

    systemctl enable unattended-upgrades > /dev/null 2>&1
    log_success "Unattended-upgrades configuré (security patches auto)"
}

# ============================================================
# 2. Sysctl hardening (réseau + kernel)
# ============================================================
setup_sysctl() {
    log_info "Hardening sysctl (réseau/kernel)..."

    cat > /etc/sysctl.d/99-hardening.conf <<'EOF'
# ---- Réseau ----
# Activer SYN cookies (protection SYN flood)
net.ipv4.tcp_syncookies = 1

# Ignorer les pings broadcast (protection smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignorer les ICMP redirects (protection MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ne pas envoyer de ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Refuser le source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Logger les paquets martiens (adresses spoofées)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Protection contre le IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Désactiver IP forwarding (sauf si Docker/K8s en a besoin)
# Note: Docker le réactive automatiquement si nécessaire
net.ipv4.ip_forward = 0

# ---- Kernel ----
# Restreindre l'accès à dmesg
kernel.dmesg_restrict = 1

# Restreindre les pointeurs kernel dans /proc
kernel.kptr_restrict = 2

# Activer ASLR complet
kernel.randomize_va_space = 2

# Restreindre ptrace (un process ne peut debug que ses enfants)
kernel.yama.ptrace_scope = 1

# Protection core dump
fs.suid_dumpable = 0
EOF

    sysctl --system > /dev/null 2>&1
    log_success "Sysctl hardening appliqué"
}

# ============================================================
# 3. Création d'un user sudo (si on est root direct)
# ============================================================
setup_sudo_user() {
    log_info "Vérification de l'utilisateur sudo..."

    if [[ "$TARGET_USER" == "root" ]]; then
        log_warn "Tu es connecté en root directement."
        echo ""
        echo -e "${YELLOW}Il est recommandé de créer un utilisateur non-root avec sudo.${NC}"

        if confirm "  Créer un nouvel utilisateur sudo ?"; then
            read -r -p "  > Nom d'utilisateur : " NEW_USER < /dev/tty

            if id "$NEW_USER" &>/dev/null; then
                log_warn "L'utilisateur $NEW_USER existe déjà"
            else
                adduser --gecos "" "$NEW_USER" < /dev/tty
                usermod -aG sudo "$NEW_USER"
                log_success "Utilisateur $NEW_USER créé avec accès sudo"
            fi

            # Copier les clés SSH de root si elles existent
            if [[ -f /root/.ssh/authorized_keys ]]; then
                mkdir -p "/home/$NEW_USER/.ssh"
                cp /root/.ssh/authorized_keys "/home/$NEW_USER/.ssh/"
                chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
                chmod 700 "/home/$NEW_USER/.ssh"
                chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
                log_success "Clés SSH copiées vers $NEW_USER"
            fi
        fi
    else
        # Vérifier que l'utilisateur courant est bien sudoer
        if groups "$TARGET_USER" | grep -qE '\b(sudo|admin)\b'; then
            log_success "$TARGET_USER a déjà les droits sudo"
        else
            usermod -aG sudo "$TARGET_USER"
            log_success "$TARGET_USER ajouté au groupe sudo"
        fi
    fi
}

# ============================================================
# 4. Swap (beaucoup de VPS n'en ont pas)
# ============================================================
setup_swap() {
    log_info "Vérification du swap..."

    if swapon --show | grep -q '/'; then
        log_warn "Swap déjà actif : $(free -h | awk '/^Swap:/ {print $2}')"
        return
    fi

    # Taille du swap = min(RAM, 4G)
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
    if (( TOTAL_RAM_MB <= 2048 )); then
        SWAP_SIZE="2G"
    elif (( TOTAL_RAM_MB <= 8192 )); then
        SWAP_SIZE="4G"
    else
        SWAP_SIZE="4G"
    fi

    log_info "Création d'un swap de $SWAP_SIZE..."
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null
    swapon /swapfile

    # Ajouter au fstab si pas déjà présent
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Optimiser le swappiness pour un VPS
    cat >> /etc/sysctl.d/99-hardening.conf <<'EOF'

# Swap - réduire le swappiness (VPS)
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    sysctl --system > /dev/null 2>&1

    log_success "Swap de $SWAP_SIZE créé et activé (swappiness=10)"
}

# ============================================================
# 5. Shared memory hardening
# ============================================================
setup_shared_memory() {
    log_info "Hardening shared memory..."

    if ! grep -q '/run/shm' /etc/fstab; then
        echo 'tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0' >> /etc/fstab
        log_success "Shared memory restreint (noexec, nosuid)"
    else
        log_warn "/run/shm déjà configuré dans fstab"
    fi
}

# ============================================================
# 6. Désactiver les services inutiles
# ============================================================
disable_unused_services() {
    log_info "Désactivation des services inutiles..."

    SERVICES_TO_DISABLE=(
        "rpcbind"
        "avahi-daemon"
        "cups"
        "bluetooth"
    )

    for svc in "${SERVICES_TO_DISABLE[@]}"; do
        if systemctl is-active "$svc" &>/dev/null; then
            systemctl stop "$svc" > /dev/null 2>&1
            systemctl disable "$svc" > /dev/null 2>&1
            log_success "Service $svc désactivé"
        fi
    done
}

# ============================================================
# 7. Bannière SSH (avertissement légal)
# ============================================================
setup_ssh_banner() {
    log_info "Configuration de la bannière SSH..."

    cat > /etc/issue.net <<'EOF'
*********************************************************************
*  Authorized access only. All activity is logged and monitored.    *
*  Unauthorized access is prohibited and will be prosecuted.        *
*********************************************************************
EOF

    SSHD_CONFIG="/etc/ssh/sshd_config"
    if ! grep -q "^Banner /etc/issue.net" "$SSHD_CONFIG"; then
        echo "Banner /etc/issue.net" >> "$SSHD_CONFIG"
    fi

    # Valider et recharger
    if sshd -t 2>/dev/null; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        log_success "Bannière SSH configurée"
    else
        log_warn "Config SSH invalide, bannière non appliquée"
    fi
}

# ============================================================
# 8. Audit & logging
# ============================================================
setup_audit() {
    log_info "Configuration de l'audit..."

    if apt-cache show auditd &>/dev/null; then
        apt_install auditd audispd-plugins 2>/dev/null || apt_install auditd

        # Règles de base
        cat > /etc/audit/rules.d/hardening.rules <<'EOF'
# Surveiller les modifications de fichiers critiques
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Surveiller les commandes sudo
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k sudo_commands

# Surveiller les changements de date/heure
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
EOF

        systemctl enable auditd > /dev/null 2>&1
        systemctl restart auditd 2>/dev/null || true
        log_success "Auditd configuré"
    else
        log_warn "auditd non disponible, skip"
    fi
}

# ============================================================
# 9. Restreindre cron et at
# ============================================================
restrict_cron() {
    log_info "Restriction de l'accès à cron/at..."

    # Seul root et les sudoers peuvent utiliser cron
    echo "root" > /etc/cron.allow 2>/dev/null || true
    if [[ "$TARGET_USER" != "root" ]]; then
        echo "$TARGET_USER" >> /etc/cron.allow 2>/dev/null || true
    fi

    echo "root" > /etc/at.allow 2>/dev/null || true
    if [[ "$TARGET_USER" != "root" ]]; then
        echo "$TARGET_USER" >> /etc/at.allow 2>/dev/null || true
    fi

    # Permissions sur les répertoires cron
    chmod 700 /etc/cron.d 2>/dev/null || true
    chmod 700 /etc/cron.daily 2>/dev/null || true
    chmod 700 /etc/cron.hourly 2>/dev/null || true
    chmod 700 /etc/cron.weekly 2>/dev/null || true
    chmod 700 /etc/cron.monthly 2>/dev/null || true

    log_success "Accès cron/at restreint"
}

# ============================================================
# 10. Permissions fichiers sensibles
# ============================================================
harden_file_permissions() {
    log_info "Durcissement des permissions fichiers..."

    chmod 600 /etc/crontab 2>/dev/null || true
    chmod 600 /etc/ssh/sshd_config 2>/dev/null || true
    chmod 640 /etc/shadow 2>/dev/null || true
    chmod 644 /etc/passwd 2>/dev/null || true
    chmod 600 /boot/grub/grub.cfg 2>/dev/null || true

    log_success "Permissions fichiers durcies"
}

# ============================================================
# Exécution
# ============================================================
setup_unattended_upgrades
setup_sysctl
setup_sudo_user
setup_swap
setup_shared_memory
disable_unused_services
setup_ssh_banner
setup_audit
restrict_cron
harden_file_permissions

log_section "Hardening VPS terminé"
echo -e "${GREEN}Résumé :${NC}"
echo "  - Mises à jour de sécurité automatiques"
echo "  - Sysctl réseau/kernel durci"
echo "  - Swap configuré"
echo "  - Shared memory restreint"
echo "  - Services inutiles désactivés"
echo "  - Bannière SSH active"
echo "  - Audit logs activés"
echo "  - Cron/at restreints"
echo "  - Permissions fichiers durcies"
