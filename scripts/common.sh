#!/usr/bin/env bash
# Fonctions partagées entre tous les scripts

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${CYAN}========== $* ==========${NC}\n"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en root (sudo)"
        exit 1
    fi
}

is_installed() {
    command -v "$1" &>/dev/null
}

apt_install() {
    log_info "Installation de: $*"
    apt-get install -y "$@" > /dev/null
    log_success "$* installé(s)"
}

# Confirm via /dev/tty pour fonctionner même quand stdin est un pipe
confirm() {
    local prompt="${1:-Continuer ?} [o/N] "
    if [[ -t 0 ]] || [[ -e /dev/tty ]]; then
        read -r -p "$prompt" response < /dev/tty
        [[ "$response" =~ ^[oOyY]$ ]]
    else
        # Non-interactif : pas de confirmation possible
        return 1
    fi
}

# Récupérer le home d'un user de façon safe
get_user_home() {
    getent passwd "$1" | cut -d: -f6
}
