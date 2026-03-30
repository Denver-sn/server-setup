#!/usr/bin/env bash
# Kubernetes tools : kubectl, helm, k9s

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Kubernetes Tools"

# Dépendances
is_installed curl || apt_install curl
is_installed jq   || apt_install jq

ARCH=$(dpkg --print-architecture)

# kubectl
if is_installed kubectl; then
    log_warn "kubectl déjà installé"
else
    log_info "Installation de kubectl..."
    curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
        -o /usr/local/bin/kubectl
    chmod +x /usr/local/bin/kubectl
    log_success "kubectl installé"
fi

# helm
if is_installed helm; then
    log_warn "Helm déjà installé"
else
    log_info "Installation de Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_success "Helm installé"
fi

# k9s
if is_installed k9s; then
    log_warn "k9s déjà installé"
else
    log_info "Installation de k9s..."
    K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" \
        -o /tmp/k9s.tar.gz
    tar -C /usr/local/bin -xzf /tmp/k9s.tar.gz k9s
    chmod +x /usr/local/bin/k9s
    rm -f /tmp/k9s.tar.gz
    log_success "k9s installé"
fi
