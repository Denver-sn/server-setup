#!/usr/bin/env bash
# ============================================================
#  Bootstrap - Télécharge le repo et lance le setup
#
#  Usage:
#    curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash
#    curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash -s -- --all
#    curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash -s -- --module docker dokploy
# ============================================================

set -euo pipefail

REPO="Denver-sn/server-setup"
BRANCH="main"
INSTALL_DIR="/tmp/server-setup"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Nettoyage garanti même en cas d'erreur
cleanup() {
    rm -rf "$INSTALL_DIR"
}
trap cleanup EXIT

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║            Server Setup - Bootstrap Installer         ║"
echo "  ║       github.com/Denver-sn/server-setup               ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Vérifier root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Ce script doit être exécuté en root (sudo)"
    exit 1
fi

# Installer git si absent
if ! command -v git &>/dev/null; then
    echo -e "${GREEN}[INFO]${NC} Installation de git..."
    apt-get update > /dev/null 2>&1
    apt-get install -y git > /dev/null
fi

# Télécharger le repo
rm -rf "$INSTALL_DIR"
echo -e "${GREEN}[INFO]${NC} Téléchargement du repo..."
git clone --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$INSTALL_DIR"

chmod +x "$INSTALL_DIR/setup.sh" "$INSTALL_DIR/scripts/"*.sh

# Si aucun argument passé via curl pipe, forcer le mode interactif ou --all
echo -e "${GREEN}[INFO]${NC} Lancement du setup...\n"
bash "$INSTALL_DIR/setup.sh" "$@"
