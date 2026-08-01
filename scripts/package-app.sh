#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/Mirror Relay.app"
CONTENTS_DIR="${APP_DIR}/Contents"
IDENTITY="${MIRROR_RELAY_SIGN_IDENTITY:--}"
PACKAGE_VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")
PLIST_VERSION=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleShortVersionString" \
  "${PROJECT_DIR}/native/App/Info.plist")

if [[ "${PACKAGE_VERSION}" != "${PLIST_VERSION}" ]]; then
  print -u2 "Version mismatch: package.json=${PACKAGE_VERSION}, Info.plist=${PLIST_VERSION}"
  exit 1
fi

swift build -c release --package-path "${PROJECT_DIR}/native"

case "${APP_DIR}" in
  "${PROJECT_DIR}/dist/Mirror Relay.app") ;;
  *) print -u2 "Refusing to package an unexpected app path"; exit 1 ;;
esac

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Helpers" "${CONTENTS_DIR}/Resources"
cp "${PROJECT_DIR}/native/.build/release/mirror-relay" "${CONTENTS_DIR}/MacOS/Mirror Relay"
cp "${PROJECT_DIR}/native/.build/release/mirror-relayctl" "${CONTENTS_DIR}/Helpers/mirror-relay"
cp "${PROJECT_DIR}/native/App/Info.plist" "${CONTENTS_DIR}/Info.plist"
ditto "${PROJECT_DIR}/public" "${CONTENTS_DIR}/Resources/public"
chmod 755 "${CONTENTS_DIR}/MacOS/Mirror Relay" "${CONTENTS_DIR}/Helpers/mirror-relay"

sign_args=(--force --options runtime --sign "${IDENTITY}")
if [[ "${IDENTITY}" != "-" ]]; then
  sign_args+=(--timestamp)
fi
codesign "${sign_args[@]}" "${CONTENTS_DIR}/Helpers/mirror-relay"
codesign "${sign_args[@]}" "${APP_DIR}"
"${SCRIPT_DIR}/verify-package.sh" "${APP_DIR}"

print "Packaged ${APP_DIR}"
print "CLI: ${CONTENTS_DIR}/Helpers/mirror-relay"
if [[ "${IDENTITY}" == "-" ]]; then
  print "Note: ad-hoc signed for local testing. Use MIRROR_RELAY_SIGN_IDENTITY with a stable Apple Development or Developer ID identity to preserve permissions across rebuilds."
fi
