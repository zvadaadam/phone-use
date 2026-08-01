#!/bin/zsh
set -euo pipefail

if [[ "$#" != 2 ]]; then
  print -u2 "Usage: create-dmg.sh <app-bundle> <output.dmg>"
  exit 2
fi

APP_DIR="${1:A}"
DMG="${2:A}"
STAGE_DIR=$(mktemp -d /tmp/mirror-relay-dmg.XXXXXX)

cleanup() {
  case "${STAGE_DIR}" in
    /tmp/mirror-relay-dmg.*) rm -rf "${STAGE_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

[[ -d "${APP_DIR}" && "${APP_DIR}" == *.app ]] || {
  print -u2 "DMG creation failed: expected an app bundle at ${APP_DIR}"
  exit 1
}
[[ "${DMG}" == *.dmg && "${DMG}" != "/" ]] || {
  print -u2 "DMG creation failed: expected an explicit .dmg output path"
  exit 1
}

mkdir -p "${DMG:h}"
rm -f "${DMG}"
ditto "${APP_DIR}" "${STAGE_DIR}/Mirror Relay.app"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create \
  -volname "Mirror Relay" \
  -srcfolder "${STAGE_DIR}" \
  -format UDZO \
  -ov \
  "${DMG}" >/dev/null
hdiutil verify "${DMG}" >/dev/null

print "Created disk image: ${DMG}"
