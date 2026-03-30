#!/usr/bin/env bash
# Zsh + Oh My Zsh + Tmux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Shell (Zsh + Oh My Zsh + Tmux)"

# Dépendances
apt_install zsh tmux curl git

# Déterminer l'utilisateur cible
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")

# Oh My Zsh
if [[ ! -d "$TARGET_HOME/.oh-my-zsh" ]]; then
    log_info "Installation de Oh My Zsh pour $TARGET_USER..."
    sudo -u "$TARGET_USER" bash -c \
        'export RUNZSH=no CHSH=no; curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh' \
        < /dev/null
    log_success "Oh My Zsh installé"
else
    log_warn "Oh My Zsh déjà installé"
fi

# Plugins
ZSH_CUSTOM="$TARGET_HOME/.oh-my-zsh/custom"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    sudo -u "$TARGET_USER" git clone --depth 1 \
        https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    sudo -u "$TARGET_USER" git clone --depth 1 \
        https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Changer le shell par défaut
usermod -s "$(which zsh)" "$TARGET_USER"

log_success "Zsh configuré comme shell par défaut pour $TARGET_USER"
