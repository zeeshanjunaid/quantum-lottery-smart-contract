#!/usr/bin/env zsh
set -euo pipefail

echo "--- zsh version ---"
zsh --version

echo "--- checking dotfiles syntax ---"
zsh -n ~/.zshrc ~/.zprofile ~/.zlogin ~/.zshenv || echo "syntax errors found in one of the dotfiles"

echo "--- tracing login shell (-ilx) ---"
echo "Re-run manually to inspect output if needed: zsh -ilx"

exit 0
