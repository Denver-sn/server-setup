#!/usr/bin/env bash
# Terraform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Terraform"

if is_installed terraform; then
    log_warn "Terraform déjà installé : $(terraform version | head -1)"
else
    log_info "Installation de Terraform..."

    is_installed curl       || apt_install curl
    is_installed gpg        || apt_install gnupg
    is_installed lsb_release || apt_install lsb-release

    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

    CODENAME=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
        | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

    apt-get update > /dev/null 2>&1
    apt_install terraform

    log_success "Terraform installé : $(terraform version | head -1)"
fi
