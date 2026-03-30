#!/usr/bin/env bash
# Dokploy - PaaS self-hosted (alternative à Vercel/Netlify)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Dokploy"

# Dokploy nécessite Docker
if ! is_installed docker; then
    log_error "Docker est requis pour Dokploy. Lance d'abord le script Docker."
    exit 1
fi

log_info "Installation de Dokploy..."
curl -sSL https://dokploy.com/install.sh | sh

log_success "Dokploy installé"
log_info "Accès via : http://<IP_DU_SERVEUR>:3000"
log_info "N'oublie pas d'ouvrir le port 3000 dans le firewall si nécessaire :"
log_info "  ufw allow 3000/tcp"
