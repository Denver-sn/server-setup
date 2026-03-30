#!/usr/bin/env bash
# Docker + Docker Compose

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Docker & Docker Compose"

if is_installed docker; then
    log_warn "Docker déjà installé : $(docker --version)"
else
    log_info "Installation de Docker..."

    apt_install ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-$UBUNTU_CODENAME}")
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update > /dev/null 2>&1
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_success "Docker installé : $(docker --version)"
fi

# Ajouter l'utilisateur au groupe docker
TARGET_USER="${SUDO_USER:-$USER}"
if ! groups "$TARGET_USER" | grep -q docker; then
    usermod -aG docker "$TARGET_USER"
    log_success "$TARGET_USER ajouté au groupe docker"
fi

# Activer et démarrer
systemctl enable docker > /dev/null 2>&1
systemctl start docker

log_success "Docker prêt"
