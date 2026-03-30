#!/usr/bin/env bash
# Go lang

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Go"

if [[ -x /usr/local/go/bin/go ]]; then
    log_warn "Go déjà installé : $(/usr/local/go/bin/go version)"
else
    # Récupérer la dernière version stable
    log_info "Récupération de la dernière version de Go..."
    GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -1)
    ARCH=$(dpkg --print-architecture)

    log_info "Installation de $GO_VERSION..."
    curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz

    # Profil global
    cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF

    log_success "$GO_VERSION installé"
fi

log_info "Go disponible après re-login ou : source /etc/profile.d/go.sh"
