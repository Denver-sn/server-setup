# Server Setup

Scripts modulaires pour configurer un serveur Ubuntu/Debian from scratch. Un seul `curl` et c'est parti.

## Quick Start

```bash
# Menu interactif
curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash

# Tout installer
curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash -s -- --all

# Modules specifiques
curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash -s -- --module system docker dokploy

# Lister les modules
curl -sSL https://raw.githubusercontent.com/Denver-sn/server-setup/main/install.sh | sudo bash -s -- --list
```

## Modules

| Module | Description |
|---|---|
| `system` | Update systeme, paquets essentiels (curl, wget, git, htop, btop, jq, etc.) |
| `security` | UFW (firewall), fail2ban, SSH hardening |
| `hardening` | Hardening VPS : auto-updates, sysctl, swap, audit, user sudo, banniere SSH |
| `shell` | Zsh + Oh My Zsh + plugins (autosuggestions, syntax-highlighting) + Tmux |
| `docker` | Docker CE + Docker Compose plugin |
| `node` | NVM + Node.js LTS + pnpm + yarn |
| `python` | pyenv + derniere version stable + pipx |
| `go` | Go lang |
| `k8s-tools` | kubectl, Helm, k9s |
| `terraform` | Terraform (repo HashiCorp) |
| `dokploy` | Dokploy - PaaS self-hosted |
| `dotfiles` | Symlink dotfiles (.zshrc, .vimrc, .gitconfig, .tmux.conf, .aliases) |

## Structure

```
server-setup/
├── install.sh          # Bootstrap (curl | bash)
├── setup.sh            # Menu interactif principal
├── scripts/
│   ├── common.sh       # Fonctions partagees
│   ├── system.sh
│   ├── security.sh
│   ├── hardening.sh
│   ├── shell.sh
│   ├── docker.sh
│   ├── node.sh
│   ├── python.sh
│   ├── go.sh
│   ├── k8s-tools.sh
│   ├── terraform.sh
│   ├── dokploy.sh
│   └── dotfiles.sh
└── dotfiles/
    ├── .zshrc
    ├── .vimrc
    ├── .gitconfig
    ├── .tmux.conf
    └── .aliases
```

## Usage local

```bash
git clone https://github.com/Denver-sn/server-setup.git
cd server-setup
sudo bash setup.sh
```

## Notes

- Chaque script est **idempotent** : il verifie si l'outil est deja installe avant d'agir
- Les dotfiles existants sont **backup** en `.bak` avant d'etre remplaces
- SSH hardening desactive le password auth seulement si une cle SSH est detectee
- Le hardening VPS configure le sysctl, swap, audit logs, et mises a jour auto de securite
- Dokploy necessite Docker (installe Docker d'abord)
- Reconnecte-toi apres l'install pour appliquer les changements shell (zsh)
