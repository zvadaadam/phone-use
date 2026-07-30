#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/Mirror Relay.app"
CONTENTS_DIR="${APP_DIR}/Contents"
IDENTITY="${MIRROR_RELAY_SIGN_IDENTITY:--}"

swift build -c release --package-path "${PROJECT_DIR}/native"

case "${APP_DIR}" in
  "${PROJECT_DIR}/dist/Mirror Relay.app") ;;
  *) print -u2 "Refusing to package an unexpected app path"; exit 1 ;;
esac

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources/bin"
cp "${PROJECT_DIR}/native/.build/release/mirror-relay" "${CONTENTS_DIR}/MacOS/Mirror Relay"
cp "${PROJECT_DIR}/native/.build/release/mirror-relayctl" "${CONTENTS_DIR}/Resources/bin/mirror-relayctl"
cp "${PROJECT_DIR}/native/App/Info.plist" "${CONTENTS_DIR}/Info.plist"
ditto "${PROJECT_DIR}/public" "${CONTENTS_DIR}/Resources/public"

codesign --force --deep --options runtime --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

print "Packaged ${APP_DIR}"
if [[ "${IDENTITY}" == "-" ]]; then
  print "Note: ad-hoc signed for local testing. Use MIRROR_RELAY_SIGN_IDENTITY with a stable Apple Development or Developer ID identity to preserve permissions across rebuilds."
fi
