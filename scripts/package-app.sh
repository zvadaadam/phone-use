#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/signing-identity.sh"
APP_DIR="${PROJECT_DIR}/dist/Phone Use.app"
CONTENTS_DIR="${APP_DIR}/Contents"
REQUESTED_IDENTITY="${PHONE_USE_SIGN_IDENTITY:-}"
REQUIRE_STABLE_SIGNING="${PHONE_USE_REQUIRE_STABLE_SIGNING:-0}"
PACKAGE_VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")
PLIST_VERSION=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleShortVersionString" \
  "${PROJECT_DIR}/native/App/Info.plist")

if [[ -n "${REQUESTED_IDENTITY}" ]]; then
  if [[ "${REQUIRE_STABLE_SIGNING}" == "1" ]]; then
    IDENTITY=$(phone_use_select_development_identity "${REQUESTED_IDENTITY}")
  else
    IDENTITY=$(phone_use_resolve_identity_hash "${REQUESTED_IDENTITY}")
  fi
else
  IDENTITY=$(phone_use_select_development_identity)
  IDENTITY="${IDENTITY:--}"
fi
IDENTITY_LABEL="${IDENTITY}"
if [[ "${IDENTITY}" != "-" ]]; then
  IDENTITY_LABEL=$(phone_use_identity_name_for_hash "${IDENTITY}")
fi

if [[ "${REQUIRE_STABLE_SIGNING}" == "1" && "${IDENTITY}" == "-" ]]; then
  print -u2 "Stable development signing is required, but no supported identity is available."
  print -u2 "Install an Apple Development identity or create the local Code Signing identity"
  print -u2 "'${PHONE_USE_LOCAL_SIGN_IDENTITY}' in Keychain Access."
  print -u2 "Run npm run signing:doctor after the certificate is installed."
  exit 1
fi

if [[ "${PACKAGE_VERSION}" != "${PLIST_VERSION}" ]]; then
  print -u2 "Version mismatch: package.json=${PACKAGE_VERSION}, Info.plist=${PLIST_VERSION}"
  exit 1
fi

swift build -c release --package-path "${PROJECT_DIR}/native"

case "${APP_DIR}" in
  "${PROJECT_DIR}/dist/Phone Use.app") ;;
  *) print -u2 "Refusing to package an unexpected app path"; exit 1 ;;
esac

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Helpers" "${CONTENTS_DIR}/Resources"
cp "${PROJECT_DIR}/native/.build/release/phone-use-app" "${CONTENTS_DIR}/MacOS/Phone Use"
cp "${PROJECT_DIR}/native/.build/release/phone-use" "${CONTENTS_DIR}/Helpers/phone-use"
cp "${PROJECT_DIR}/native/App/Info.plist" "${CONTENTS_DIR}/Info.plist"
ditto "${PROJECT_DIR}/public" "${CONTENTS_DIR}/Resources/public"
chmod 755 "${CONTENTS_DIR}/MacOS/Phone Use" "${CONTENTS_DIR}/Helpers/phone-use"

sign_args=(--force --options runtime --sign "${IDENTITY}")
if [[ "${IDENTITY_LABEL}" == "Developer ID Application:"* ]]; then
  sign_args+=(--timestamp)
fi
codesign "${sign_args[@]}" "${CONTENTS_DIR}/Helpers/phone-use"
codesign "${sign_args[@]}" "${APP_DIR}"
PHONE_USE_REQUIRE_STABLE_SIGNING="${REQUIRE_STABLE_SIGNING}" \
PHONE_USE_EXPECTED_SIGNING_HASH="${IDENTITY/-/}" \
  "${SCRIPT_DIR}/verify-package.sh" "${APP_DIR}"

print "Packaged ${APP_DIR}"
print "CLI: ${CONTENTS_DIR}/Helpers/phone-use"
if [[ "${IDENTITY}" == "-" ]]; then
  print "WARNING: ad-hoc signed. Use npm run package:dev for a stable development identity."
else
  print "Signed with stable identity: ${IDENTITY_LABEL} (${IDENTITY})"
fi
