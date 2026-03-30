#!/usr/bin/env bash
# Mise à jour système + paquets essentiels

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Mise à jour système & paquets essentiels"

log_info "Mise à jour des dépôts..."
apt-get update > /dev/null 2>&1

log_info "Upgrade des paquets..."
apt-get upgrade -y > /dev/null

log_info "Installation des paquets essentiels..."
apt_install \
    build-essential \
    curl \
    wget \
    git \
    unzip \
    zip \
    htop \
    ncdu \
    tree \
    jq \
    net-tools \
    dnsutils \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    locales \
    sudo

# btop : dispo nativement sur 23.04+, sinon snap
if apt-cache show btop &>/dev/null; then
    apt_install btop
elif is_installed snap; then
    log_info "btop non dispo dans apt, installation via snap..."
    snap install btop
    log_success "btop installé via snap"
else
    log_warn "btop non disponible (ni apt ni snap), skip"
fi

log_info "Configuration des locales..."
locale-gen en_US.UTF-8 > /dev/null 2>&1
update-locale LANG=en_US.UTF-8 > /dev/null 2>&1

log_info "Configuration du timezone..."
timedatectl set-timezone UTC 2>/dev/null || {
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    echo "UTC" > /etc/timezone
}

log_info "Nettoyage apt..."
apt-get autoremove -y > /dev/null
apt-get clean > /dev/null

log_success "Système mis à jour et paquets essentiels installés"
