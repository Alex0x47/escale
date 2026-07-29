#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

git -C "$PROJECT_ROOT" config core.hooksPath .githooks
echo "Installed Escale Git hooks for $PROJECT_ROOT"
