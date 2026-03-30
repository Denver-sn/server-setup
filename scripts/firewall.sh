#!/usr/bin/env bash
# ============================================================
#  Firewall avancé pour VPS
#  - UFW avancé avec rate limiting
#  - Fix Docker bypass UFW (CRITIQUE)
#  - Anti-portscan
#  - Gestion fine des ports par service
#  - Protection brute force au niveau iptables
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Firewall avancé"

# Lire le port SSH (défini par security.sh)
SSH_PORT=22
[[ -f /etc/server-setup-ssh-port ]] && SSH_PORT=$(cat /etc/server-setup-ssh-port)

# ============================================================
# 1. UFW : reset propre + règles de base
# ============================================================
setup_ufw_base() {
    log_info "Configuration UFW avancée..."

    apt_install ufw

    # Reset propre (sans prompt)
    echo "y" | ufw reset > /dev/null 2>&1

    # Politique par défaut
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    ufw default deny routed > /dev/null

    log_success "UFW reset avec politique deny incoming / allow outgoing / deny routed"
}

# ============================================================
# 2. Ports autorisés avec rate limiting
# ============================================================
setup_ufw_rules() {
    log_info "Configuration des règles de ports..."

    # SSH avec rate limiting (6 connexions en 30s = ban)
    if (( SSH_PORT == 22 )); then
        ufw limit ssh comment 'SSH rate-limited' > /dev/null
    else
        ufw limit "${SSH_PORT}/tcp" comment 'SSH rate-limited' > /dev/null
    fi

    # HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP' > /dev/null
    ufw allow 443/tcp comment 'HTTPS' > /dev/null

    # DNS (sortant seulement, déjà ok par default allow outgoing)

    # Dokploy (si utilisé)
    if is_installed docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -qi dokploy; then
        ufw allow 3000/tcp comment 'Dokploy UI' > /dev/null
        log_info "Port 3000 ouvert (Dokploy détecté)"
    fi

    log_success "Règles de base configurées (SSH rate-limited, HTTP, HTTPS)"
}

# ============================================================
# 3. Fix Docker bypass UFW (CRITIQUE)
#    Par défaut Docker manipule iptables directement
#    et bypass complètement UFW. Tous les ports exposés
#    dans docker-compose sont accessibles au monde entier.
# ============================================================
fix_docker_ufw() {
    log_info "Fix Docker bypass UFW (CRITIQUE)..."

    if ! is_installed docker; then
        log_warn "Docker non installé, skip du fix Docker/UFW"
        return
    fi

    DOCKER_CONF="/etc/docker/daemon.json"

    # Méthode 1: Désactiver la manipulation iptables par Docker
    # et utiliser les UFW DOCKER rules à la place
    if [[ -f "$DOCKER_CONF" ]]; then
        # Vérifier si iptables est déjà configuré
        if grep -q '"iptables"' "$DOCKER_CONF"; then
            log_warn "Config iptables Docker déjà présente dans $DOCKER_CONF"
        else
            # Injecter la config dans le JSON existant
            TMP_CONF=$(mktemp)
            jq '. + {"iptables": false}' "$DOCKER_CONF" > "$TMP_CONF" 2>/dev/null || {
                # Si jq échoue (JSON malformé), backup et recréer
                cp "$DOCKER_CONF" "${DOCKER_CONF}.bak"
                echo '{"iptables": false}' > "$TMP_CONF"
            }
            mv "$TMP_CONF" "$DOCKER_CONF"
        fi
    else
        mkdir -p /etc/docker
        cat > "$DOCKER_CONF" <<'EOF'
{
    "iptables": false
}
EOF
    fi

    # Méthode 2: UFW DOCKER chain via after.rules
    # Permet de contrôler l'accès aux containers via UFW
    UFW_AFTER="/etc/ufw/after.rules"

    if ! grep -q 'ufw-docker' "$UFW_AFTER" 2>/dev/null; then
        cat >> "$UFW_AFTER" <<'RULES'

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]

-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
RULES
        log_success "UFW DOCKER chain ajoutée dans after.rules"
    else
        log_warn "UFW DOCKER chain déjà configurée"
    fi

    # Redémarrer Docker pour appliquer
    systemctl restart docker 2>/dev/null || true
    log_success "Docker ne bypass plus UFW"
    log_info "Pour exposer un port Docker via UFW :"
    log_info "  ufw route allow proto tcp from any to any port 8080"
}

# ============================================================
# 4. Anti-portscan via iptables
# ============================================================
setup_anti_portscan() {
    log_info "Protection anti-portscan..."

    # Créer un script iptables pour anti-portscan
    cat > /etc/ufw/before.rules.d/anti-portscan.rules 2>/dev/null <<'EOF' || true
# Anti-portscan rules loaded via UFW
EOF

    # Ajouter les règles anti-portscan dans before.rules
    UFW_BEFORE="/etc/ufw/before.rules"

    if ! grep -q 'anti-portscan' "$UFW_BEFORE" 2>/dev/null; then
        # Insérer avant le COMMIT final
        sed -i '/^COMMIT$/i \
# BEGIN ANTI-PORTSCAN\
-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP\
-A ufw-before-input -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP\
-A ufw-before-input -p tcp --tcp-flags SYN,RST SYN,RST -j DROP\
-A ufw-before-input -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP\
-A ufw-before-input -f -j DROP\
# END ANTI-PORTSCAN' "$UFW_BEFORE"

        log_success "Règles anti-portscan ajoutées (NULL scan, XMAS, fragments)"
    else
        log_warn "Règles anti-portscan déjà en place"
    fi
}

# ============================================================
# 5. Rate limiting global (protection brute force layer iptables)
# ============================================================
setup_rate_limiting() {
    log_info "Rate limiting iptables..."

    UFW_BEFORE="/etc/ufw/before.rules"

    if ! grep -q 'RATE-LIMIT' "$UFW_BEFORE" 2>/dev/null; then
        # Insérer les règles avant le premier COMMIT
        TMPFILE=$(mktemp)
        awk -v ssh_port="$SSH_PORT" '
        /^COMMIT$/ && !done {
            print "# BEGIN RATE-LIMIT"
            print "-A ufw-before-input -p tcp --dport " ssh_port " -m state --state NEW -m recent --set --name SSH"
            print "-A ufw-before-input -p tcp --dport " ssh_port " -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP"
            print "-A ufw-before-input -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --set --name HTTP"
            print "-A ufw-before-input -p tcp -m multiport --dports 80,443 -m state --state NEW -m recent --update --seconds 1 --hitcount 20 --name HTTP -j DROP"
            print "# END RATE-LIMIT"
            done=1
        }
        { print }
        ' "$UFW_BEFORE" > "$TMPFILE"
        mv "$TMPFILE" "$UFW_BEFORE"

        log_success "Rate limiting configuré (SSH: 4/min, HTTP: 20/sec)"
    else
        log_warn "Rate limiting déjà configuré"
    fi
}

# ============================================================
# 6. Protection ICMP (ping flood)
# ============================================================
setup_icmp_protection() {
    log_info "Protection ICMP..."

    UFW_BEFORE="/etc/ufw/before.rules"

    # Modifier les règles ICMP existantes dans before.rules
    # Limiter le ping au lieu de le bloquer complètement
    if ! grep -q 'icmp-rate-limit' "$UFW_BEFORE" 2>/dev/null; then
        sed -i '/^COMMIT$/i \
# BEGIN ICMP-RATE-LIMIT\
-A ufw-before-input -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT\
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP\
# END ICMP-RATE-LIMIT' "$UFW_BEFORE"

        log_success "ICMP rate-limited (1/sec, burst 4)"
    else
        log_warn "ICMP rate limiting déjà configuré"
    fi
}

# ============================================================
# 7. Logging des connexions bloquées
# ============================================================
setup_logging() {
    log_info "Configuration du logging UFW..."

    ufw logging medium > /dev/null 2>&1

    # Logrotate pour les logs UFW
    cat > /etc/logrotate.d/ufw <<'EOF'
/var/log/ufw.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog adm
}
EOF

    log_success "Logging UFW activé (medium) avec rotation"
}

# ============================================================
# 8. Helper : ouvrir un port Docker via UFW
# ============================================================
install_ufw_docker_helper() {
    log_info "Installation du helper ufw-docker..."

    cat > /usr/local/bin/ufw-docker <<'SCRIPT'
#!/usr/bin/env bash
# Helper pour gérer les ports Docker via UFW
# Usage:
#   ufw-docker allow <container> <port>/tcp
#   ufw-docker deny <container>
#   ufw-docker list
#   ufw-docker status

set -euo pipefail

case "${1:-help}" in
    allow)
        CONTAINER="${2:?Usage: ufw-docker allow <container> <port>/tcp}"
        PORT="${3:?Usage: ufw-docker allow <container> <port>/tcp}"
        CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
        if [[ -z "$CONTAINER_IP" ]]; then
            echo "Container '$CONTAINER' non trouvé ou pas d'IP"
            exit 1
        fi
        ufw route allow proto tcp from any to "$CONTAINER_IP" port "${PORT%/*}"
        echo "Port $PORT ouvert pour le container $CONTAINER ($CONTAINER_IP)"
        ;;
    deny)
        CONTAINER="${2:?Usage: ufw-docker deny <container>}"
        CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
        if [[ -z "$CONTAINER_IP" ]]; then
            echo "Container '$CONTAINER' non trouvé ou pas d'IP"
            exit 1
        fi
        ufw route delete allow proto tcp from any to "$CONTAINER_IP"
        echo "Règles supprimées pour le container $CONTAINER"
        ;;
    list)
        ufw status numbered | grep -i 'route'
        ;;
    status)
        echo "=== UFW Status ==="
        ufw status verbose
        echo ""
        echo "=== Ports Docker exposés ==="
        docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null || echo "Docker non dispo"
        echo ""
        echo "=== Ports en écoute ==="
        ss -tlnp | grep -v '127.0.0' | grep LISTEN
        ;;
    *)
        echo "Usage: ufw-docker {allow|deny|list|status}"
        echo ""
        echo "  allow <container> <port>/tcp   Ouvrir un port pour un container"
        echo "  deny <container>               Fermer les ports d'un container"
        echo "  list                           Lister les règles route UFW"
        echo "  status                         Statut complet (UFW + Docker + ports)"
        ;;
esac
SCRIPT

    chmod +x /usr/local/bin/ufw-docker
    log_success "Helper ufw-docker installé dans /usr/local/bin/ufw-docker"
    log_info "Usage : ufw-docker allow <container> <port>/tcp"
}

# ============================================================
# 9. Activer UFW et afficher le status
# ============================================================
activate_ufw() {
    log_info "Activation de UFW..."
    echo "y" | ufw enable > /dev/null 2>&1
    ufw reload > /dev/null 2>&1
    log_success "UFW activé et rechargé"
}

show_status() {
    log_section "Status Firewall"
    ufw status verbose
    echo ""
    log_info "Ports actuellement en écoute :"
    ss -tlnp | grep LISTEN | awk '{printf "  %-6s %s\n", $1, $4}'
}

# ============================================================
# Exécution
# ============================================================
setup_ufw_base
setup_ufw_rules
fix_docker_ufw
setup_anti_portscan
setup_rate_limiting
setup_icmp_protection
setup_logging
install_ufw_docker_helper
activate_ufw
show_status

log_section "Firewall configuré"
echo -e "${GREEN}Résumé :${NC}"
echo "  - UFW : deny incoming / allow outgoing / deny routed"
echo "  - SSH port $SSH_PORT : rate-limited (4 new conn/min max)"
echo "  - HTTP/HTTPS : ouverts avec rate limit (20 conn/sec)"
echo "  - Docker : ne bypass plus UFW (iptables: false)"
echo "  - Anti-portscan : NULL, XMAS, SYN/RST, fragments bloqués"
echo "  - ICMP : rate-limited (1/sec)"
echo "  - Logging UFW medium + logrotate"
echo ""
echo -e "${YELLOW}Pour exposer un port Docker :${NC}"
echo "  ufw-docker allow <container> <port>/tcp"
echo "  ufw-docker status"
