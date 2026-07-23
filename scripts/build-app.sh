#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_BUNDLE="$PROJECT_ROOT/dist/Gouvernail.app"
CONTENTS="$APP_BUNDLE/Contents"
ICONSET="$(mktemp -d)/AppIcon.iconset"
BUILD_CONFIGURATION="${GOUVERNAIL_BUILD_CONFIGURATION:-release}"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ICONSET"

swift build --package-path "$PROJECT_ROOT" -c "$BUILD_CONFIGURATION"
cp "$PROJECT_ROOT/.build/$BUILD_CONFIGURATION/Gouvernail" "$CONTENTS/MacOS/Gouvernail"
cp "$PROJECT_ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

RESOURCE_BUNDLE="$PROJECT_ROOT/.build/$BUILD_CONFIGURATION/Gouvernail_Gouvernail.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
fi

for size in 16 32 128 256 512; do
  magick "$PROJECT_ROOT/Assets/AppIcon.png" \
    -resize "${size}x${size}!" +repage -strip -depth 8 \
    "PNG32:$ICONSET/icon_${size}x${size}.png"
  double_size=$((size * 2))
  magick "$PROJECT_ROOT/Assets/AppIcon.png" \
    -resize "${double_size}x${double_size}!" +repage -strip -depth 8 \
    "PNG32:$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

SIGNING_IDENTITY="${GOUVERNAIL_CODESIGN_IDENTITY:-}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  echo "Signed with $SIGNING_IDENTITY"
else
  DEVELOPMENT_IDENTITIES=("${(@f)$(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p')}")
  for CANDIDATE_IDENTITY in "${DEVELOPMENT_IDENTITIES[@]}"; do
    [[ -z "$CANDIDATE_IDENTITY" ]] && continue
    if codesign --force --deep --sign "$CANDIDATE_IDENTITY" "$APP_BUNDLE" >/dev/null 2>&1 && \
       codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1; then
      SIGNING_IDENTITY="$CANDIDATE_IDENTITY"
      break
    fi
  done

  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signed with $SIGNING_IDENTITY"
  else
    codesign --force --deep --sign - "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    echo "No trusted Apple Development identity was found; used an ad-hoc signature."
    echo "Keychain may ask again after the executable changes."
  fi
fi

echo "$APP_BUNDLE"
