#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/Mirror Relay.app"
VERSION=$(node -p "require('${PROJECT_DIR}/package.json').version")
ARCHIVE="${PROJECT_DIR}/dist/Mirror Relay-${VERSION}.zip"

if [[ -z "${MIRROR_RELAY_SIGN_IDENTITY:-}" ]]; then
  print -u2 "Set MIRROR_RELAY_SIGN_IDENTITY to a Developer ID Application identity."
  exit 1
fi
if [[ -z "${MIRROR_RELAY_NOTARY_PROFILE:-}" ]]; then
  print -u2 "Set MIRROR_RELAY_NOTARY_PROFILE to a notarytool keychain profile."
  exit 1
fi

MIRROR_RELAY_SIGN_IDENTITY="${MIRROR_RELAY_SIGN_IDENTITY}" \
  "${SCRIPT_DIR}/package-app.sh"

case "${ARCHIVE}" in
  "${PROJECT_DIR}/dist/Mirror Relay-${VERSION}.zip") ;;
  *) print -u2 "Refusing to package an unexpected archive path"; exit 1 ;;
esac

rm -f "${ARCHIVE}"
ditto -c -k --keepParent "${APP_DIR}" "${ARCHIVE}"
xcrun notarytool submit "${ARCHIVE}" \
  --keychain-profile "${MIRROR_RELAY_NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${APP_DIR}"
xcrun stapler validate "${APP_DIR}"
spctl --assess --type execute --verbose=4 "${APP_DIR}"

rm -f "${ARCHIVE}"
ditto -c -k --keepParent "${APP_DIR}" "${ARCHIVE}"
print "Release-ready archive: ${ARCHIVE}"
