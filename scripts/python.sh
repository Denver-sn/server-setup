#!/usr/bin/env bash
# Python + pyenv + pipx

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Python (pyenv + pipx)"

# Dépendances pour compiler Python
apt_install \
    curl \
    git \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")

# pyenv
if [[ ! -d "$TARGET_HOME/.pyenv" ]]; then
    log_info "Installation de pyenv..."
    PYENV_SCRIPT=$(mktemp)
    curl -fsSL https://pyenv.run -o "$PYENV_SCRIPT"
    sudo -u "$TARGET_USER" bash "$PYENV_SCRIPT" < /dev/null
    rm -f "$PYENV_SCRIPT"
    log_success "pyenv installé"
else
    log_warn "pyenv déjà installé"
fi

# Installer Python latest stable
log_info "Installation de la dernière version stable de Python..."
sudo -u "$TARGET_USER" bash -c "
    export PYENV_ROOT=\"$TARGET_HOME/.pyenv\"
    export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
    eval \"\$(pyenv init -)\"
    LATEST=\$(pyenv install --list | grep -E '^\s+[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | tr -d ' ')
    pyenv install -s \"\$LATEST\"
    pyenv global \"\$LATEST\"
" < /dev/null

# pipx : dispo via apt sur 23.04+, sinon via pip
if apt-cache show pipx &>/dev/null; then
    apt_install pipx
else
    log_info "pipx non dispo dans apt, installation via pip..."
    sudo -u "$TARGET_USER" bash -c "
        export PYENV_ROOT=\"$TARGET_HOME/.pyenv\"
        export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
        eval \"\$(pyenv init -)\"
        pip install --user pipx
    " < /dev/null
    log_success "pipx installé via pip"
fi

sudo -u "$TARGET_USER" -H bash -c "
    export PATH=\"$TARGET_HOME/.local/bin:\$PATH\"
    pipx ensurepath
" < /dev/null 2>/dev/null || true

log_success "Python configuré avec pyenv et pipx"
