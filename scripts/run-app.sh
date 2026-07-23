#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

GOUVERNAIL_BUILD_CONFIGURATION=debug "$PROJECT_ROOT/scripts/build-app.sh"
open "$PROJECT_ROOT/dist/Gouvernail.app"
