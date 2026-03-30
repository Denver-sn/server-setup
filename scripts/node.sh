#!/usr/bin/env bash
# Node.js via NVM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Node.js (via NVM)"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")
NVM_DIR="$TARGET_HOME/.nvm"

if [[ ! -d "$NVM_DIR" ]]; then
    log_info "Installation de NVM..."
    # Télécharger puis exécuter (évite le conflit stdin avec curl pipe)
    NVM_SCRIPT=$(mktemp)
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh -o "$NVM_SCRIPT"
    sudo -u "$TARGET_USER" bash "$NVM_SCRIPT" < /dev/null
    rm -f "$NVM_SCRIPT"
    log_success "NVM installé"
else
    log_warn "NVM déjà installé"
fi

# Installer Node LTS
log_info "Installation de Node.js LTS..."
sudo -u "$TARGET_USER" bash -c "
    export NVM_DIR=\"$NVM_DIR\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    nvm install --lts
    nvm alias default 'lts/*'
    npm install -g pnpm yarn
" < /dev/null

log_success "Node.js LTS installé avec pnpm et yarn"
