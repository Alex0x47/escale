#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
VERSION_FILE="$PROJECT_ROOT/VERSION"

fail() {
  echo "error: $*" >&2
  exit 1
}

read_version() {
  [[ -f "$VERSION_FILE" ]] || fail "Missing $VERSION_FILE"

  local version
  version="$(tr -d '[:space:]' < "$VERSION_FILE")"
  [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] \
    || fail "VERSION must contain a semantic version such as 1.2.3"
  echo "$version"
}

case "${1:-current}" in
  current)
    read_version
    ;;

  bump-patch)
    current_version="$(read_version)"
    parts=("${(@s:.:)current_version}")
    next_version="${parts[1]}.${parts[2]}.$((parts[3] + 1))"
    echo "$next_version" > "$VERSION_FILE"
    echo "$next_version"
    ;;

  apply-to-plist)
    plist_path="${2:-}"
    [[ -n "$plist_path" ]] || fail "Usage: $0 apply-to-plist /path/to/Info.plist"
    [[ -f "$plist_path" ]] || fail "Missing plist: $plist_path"

    app_version="$(read_version)"
    build_number="${ESCALE_BUILD_NUMBER:-}"
    if [[ -z "$build_number" ]] && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      build_number="$(git -C "$PROJECT_ROOT" rev-list --count HEAD)"
    fi
    build_number="${build_number:-1}"
    [[ "$build_number" =~ '^[0-9]+$' ]] \
      || fail "ESCALE_BUILD_NUMBER must be a positive integer"
    (( build_number > 0 )) || fail "ESCALE_BUILD_NUMBER must be a positive integer"

    /usr/libexec/PlistBuddy \
      -c "Set :CFBundleShortVersionString $app_version" \
      -c "Set :CFBundleVersion $build_number" \
      "$plist_path"
    echo "Escale $app_version ($build_number)"
    ;;

  *)
    fail "Usage: $0 {current|bump-patch|apply-to-plist /path/to/Info.plist}"
    ;;
esac
