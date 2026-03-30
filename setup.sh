#!/usr/bin/env bash
# ============================================================
#  Server Setup - Script principal avec menu interactif
#
#  Usage:
#    sudo bash setup.sh              # Menu interactif
#    sudo bash setup.sh --all        # Tout installer
#    sudo bash setup.sh --module docker node dokploy
#    sudo bash setup.sh --list       # Lister les modules
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# ---- Modules disponibles ----

MODULES=(
    "system       | Mise a jour systeme + paquets essentiels"
    "security     | UFW, fail2ban, SSH hardening"
    "hardening    | Hardening VPS (sysctl, swap, audit, auto-updates)"
    "shell        | Zsh + Oh My Zsh + Tmux"
    "docker       | Docker + Docker Compose"
    "node         | Node.js (NVM + LTS + pnpm/yarn)"
    "python       | Python (pyenv + pipx)"
    "go           | Go lang"
    "k8s-tools    | kubectl, Helm, k9s"
    "terraform    | Terraform (HashiCorp)"
    "dokploy      | Dokploy (PaaS self-hosted)"
    "dotfiles     | Dotfiles (zsh, vim, git, tmux, aliases)"
)

get_module_name() {
    echo "$1" | cut -d'|' -f1 | xargs
}

show_menu() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║           SERVER SETUP - Menu Principal          ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    local i=1
    for module in "${MODULES[@]}"; do
        local name desc
        name=$(echo "$module" | cut -d'|' -f1 | xargs)
        desc=$(echo "$module" | cut -d'|' -f2 | xargs)
        printf "  ${GREEN}%2d)${NC} %-14s %s\n" "$i" "$name" "$desc"
        ((i++))
    done

    echo ""
    echo -e "  ${YELLOW} A)${NC} Tout installer (all-in-one)"
    echo -e "  ${YELLOW} S)${NC} Selection personnalisee"
    echo -e "  ${RED} Q)${NC} Quitter"
    echo ""
}

run_module() {
    local name="$1"
    local script="$SCRIPT_DIR/scripts/${name}.sh"

    if [[ -f "$script" ]]; then
        bash "$script"
    else
        log_error "Script introuvable : $script"
        return 1
    fi
}

run_all() {
    log_section "Installation complete - ALL IN ONE"

    local order=(system security hardening shell docker node python go k8s-tools terraform dokploy dotfiles)

    for mod in "${order[@]}"; do
        run_module "$mod" || log_warn "Module '$mod' a échoué, on continue..."
    done

    log_section "Installation terminee !"
    echo -e "${GREEN}Tout est installe. Reconnecte-toi pour appliquer les changements shell.${NC}"
}

run_selection() {
    echo ""
    echo -e "${YELLOW}Entre les numeros des modules a installer, separes par des espaces.${NC}"
    echo -e "${YELLOW}Exemple: 1 3 4 6 10${NC}"
    echo ""
    read -r -p "  > Choix : " choices < /dev/tty

    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#MODULES[@]} )); then
            local module="${MODULES[$((choice-1))]}"
            local name
            name=$(get_module_name "$module")
            run_module "$name" || log_warn "Module '$name' a échoué, on continue..."
        else
            log_warn "Choix invalide : $choice (ignore)"
        fi
    done

    log_section "Installation terminee !"
}

# ---- Point d'entrée ----

require_root

# Mode non-interactif : arguments en ligne de commande
if [[ $# -gt 0 ]]; then
    case "$1" in
        --all|-a)
            run_all
            exit 0
            ;;
        --module|-m)
            shift
            for mod in "$@"; do
                run_module "$mod" || log_warn "Module '$mod' a échoué, on continue..."
            done
            exit 0
            ;;
        --list|-l)
            echo "Modules disponibles :"
            for module in "${MODULES[@]}"; do
                name=$(get_module_name "$module")
                echo "  - $name"
            done
            exit 0
            ;;
        --help|-h)
            echo "Usage:"
            echo "  sudo bash setup.sh              # Menu interactif"
            echo "  sudo bash setup.sh --all         # Tout installer"
            echo "  sudo bash setup.sh --module docker node  # Modules specifiques"
            echo "  sudo bash setup.sh --list        # Lister les modules"
            exit 0
            ;;
        *)
            log_error "Option inconnue : $1"
            log_info "Utilise --help pour voir les options disponibles"
            exit 1
            ;;
    esac
fi

# Mode interactif : vérifier que /dev/tty est disponible
if ! exec 0</dev/tty 2>/dev/null; then
    log_error "Mode interactif impossible (stdin non disponible)."
    log_info "Utilise : sudo bash setup.sh --all  ou  --module <modules>"
    exit 1
fi

while true; do
    show_menu
    read -r -p "  > Choix [A/S/Q/1-${#MODULES[@]}] : " action < /dev/tty

    case "${action^^}" in
        A)
            if confirm "  Installer TOUS les modules ?"; then
                run_all
            fi
            break
            ;;
        S)
            run_selection
            break
            ;;
        Q)
            log_info "Bye!"
            exit 0
            ;;
        *)
            if [[ "$action" =~ ^[0-9]+$ ]] && (( action >= 1 && action <= ${#MODULES[@]} )); then
                module="${MODULES[$((action-1))]}"
                name=$(get_module_name "$module")
                run_module "$name"
            else
                log_warn "Choix invalide"
            fi
            ;;
    esac
done
