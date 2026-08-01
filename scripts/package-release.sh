#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/Mirror Relay.app"
VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")
DMG="${PROJECT_DIR}/dist/Mirror Relay-${VERSION}.dmg"
SHA256_FILE="${DMG}.sha256"
WORK_DMG="${PROJECT_DIR}/dist/.Mirror Relay-${VERSION}.partial.dmg"
WORK_SHA256_FILE="${PROJECT_DIR}/dist/.Mirror Relay-${VERSION}.dmg.sha256.partial"
SUBMISSION_ZIP="${PROJECT_DIR}/dist/Mirror Relay-${VERSION}-notarization.zip"

fail() {
  print -u2 "Release packaging failed: $1"
  exit 1
}

cleanup() {
  rm -f "${SUBMISSION_ZIP}" "${WORK_DMG}" "${WORK_SHA256_FILE}"
}
trap cleanup EXIT INT TERM

IDENTITY="${MIRROR_RELAY_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${MIRROR_RELAY_NOTARY_PROFILE:-}"

[[ -n "${IDENTITY}" ]] \
  || fail "set MIRROR_RELAY_SIGN_IDENTITY to a Developer ID Application identity"
[[ "${IDENTITY}" == "Developer ID Application:"* ]] \
  || fail "MIRROR_RELAY_SIGN_IDENTITY must be a Developer ID Application identity"
[[ -n "${NOTARY_PROFILE}" ]] \
  || fail "set MIRROR_RELAY_NOTARY_PROFILE to a notarytool keychain profile"
security find-identity -v -p codesigning | grep -F -- "\"${IDENTITY}\"" >/dev/null \
  || fail "the requested Developer ID identity is not available in the keychain"

case "${DMG}" in
  "${PROJECT_DIR}/dist/Mirror Relay-${VERSION}.dmg") ;;
  *) fail "unexpected disk image path" ;;
esac

MIRROR_RELAY_SIGN_IDENTITY="${IDENTITY}" "${SCRIPT_DIR}/package-app.sh"
MIRROR_RELAY_REQUIRE_DISTRIBUTION=1 \
MIRROR_RELAY_EXPECTED_ARCHS=arm64 \
  "${SCRIPT_DIR}/verify-package.sh" "${APP_DIR}"

rm -f "${SUBMISSION_ZIP}" "${WORK_DMG}" "${WORK_SHA256_FILE}"
ditto -c -k --keepParent "${APP_DIR}" "${SUBMISSION_ZIP}"
xcrun notarytool submit "${SUBMISSION_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${APP_DIR}"
xcrun stapler validate "${APP_DIR}"

"${SCRIPT_DIR}/create-dmg.sh" "${APP_DIR}" "${WORK_DMG}"
codesign --force --timestamp --sign "${IDENTITY}" "${WORK_DMG}"
xcrun notarytool submit "${WORK_DMG}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${WORK_DMG}"
xcrun stapler validate "${WORK_DMG}"

MIRROR_RELAY_REQUIRE_DISTRIBUTION=1 \
MIRROR_RELAY_REQUIRE_NOTARIZATION=1 \
MIRROR_RELAY_EXPECTED_ARCHS=arm64 \
  "${SCRIPT_DIR}/verify-package.sh" "${APP_DIR}"
codesign --verify --strict --verbose=2 "${WORK_DMG}"
hdiutil verify "${WORK_DMG}" >/dev/null
spctl --assess --type open --context context:primary-signature --verbose=4 "${WORK_DMG}"
DMG_SHA256=$(shasum -a 256 "${WORK_DMG}" | awk '{ print $1 }')
print -r -- "${DMG_SHA256}  ${DMG:t}" >"${WORK_SHA256_FILE}"
mv -f "${WORK_DMG}" "${DMG}"
mv -f "${WORK_SHA256_FILE}" "${SHA256_FILE}"

print "Release-ready disk image: ${DMG}"
print "Checksum: ${SHA256_FILE}"
