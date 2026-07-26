#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

ESCALE_BUILD_CONFIGURATION=debug "$PROJECT_ROOT/scripts/build-app.sh"
open "$PROJECT_ROOT/dist/Escale.app"
