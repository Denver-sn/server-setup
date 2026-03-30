#!/usr/bin/env bash
# Installation des dotfiles (copie si depuis /tmp, symlink sinon)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_root
log_section "Dotfiles"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(get_user_home "$TARGET_USER")
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../dotfiles" && pwd)"

# Si le repo est dans /tmp (bootstrap via install.sh), copier au lieu de symlink
# car /tmp sera nettoyé après
USE_COPY=false
if [[ "$DOTFILES_DIR" == /tmp/* ]]; then
    USE_COPY=true
fi

DOTFILES=(
    ".zshrc"
    ".vimrc"
    ".gitconfig"
    ".tmux.conf"
    ".aliases"
)

for file in "${DOTFILES[@]}"; do
    src="$DOTFILES_DIR/$file"
    dest="$TARGET_HOME/$file"

    if [[ ! -f "$src" ]]; then
        log_warn "Fichier source manquant : $src (skip)"
        continue
    fi

    # Backup si le fichier existe et n'est pas un symlink
    if [[ -f "$dest" && ! -L "$dest" ]]; then
        log_info "Backup de $dest -> ${dest}.bak"
        cp "$dest" "${dest}.bak"
    fi

    if [[ "$USE_COPY" == true ]]; then
        cp -f "$src" "$dest"
        log_success "Copié : $src -> $dest"
    else
        ln -sf "$src" "$dest"
        log_success "Symlink : $dest -> $src"
    fi

    chown "$TARGET_USER:$TARGET_USER" "$dest"
done

log_success "Dotfiles installés"
