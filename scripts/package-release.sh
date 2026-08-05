#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/Phone Use.app"
VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")
DMG="${PROJECT_DIR}/dist/Phone-Use-${VERSION}.dmg"
SHA256_FILE="${DMG}.sha256"
WORK_DMG="${PROJECT_DIR}/dist/.Phone-Use-${VERSION}.partial.dmg"
WORK_SHA256_FILE="${PROJECT_DIR}/dist/.Phone-Use-${VERSION}.dmg.sha256.partial"
SUBMISSION_ZIP="${PROJECT_DIR}/dist/Phone-Use-${VERSION}-notarization.zip"
WORK_CASK_ROOT="${PROJECT_DIR}/dist/.Phone-Use-${VERSION}.homebrew.partial"
WORK_CASK_ASSET="${WORK_CASK_ROOT}/${DMG:t}"
WORK_CASK="${WORK_CASK_ROOT}/Casks/phone-use.rb"
FINAL_CASK="${PROJECT_DIR}/dist/homebrew/Casks/phone-use.rb"
LEGACY_DMG="${PROJECT_DIR}/dist/Phone Use-${VERSION}.dmg"
LEGACY_SHA256_FILE="${LEGACY_DMG}.sha256"

fail() {
  print -u2 "Release packaging failed: $1"
  exit 1
}

[[ "${VERSION}" =~ '^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z.-]+)?$' ]] \
  || fail "package version is not a safe release version"

cleanup() {
  rm -f "${SUBMISSION_ZIP}" "${WORK_DMG}" "${WORK_SHA256_FILE}"
  case "${WORK_CASK_ROOT}" in
    "${PROJECT_DIR}/dist/.Phone-Use-${VERSION}.homebrew.partial")
      rm -rf "${WORK_CASK_ROOT}"
      ;;
  esac
}
trap cleanup EXIT INT TERM

IDENTITY="${PHONE_USE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${PHONE_USE_NOTARY_PROFILE:-}"

[[ -n "${IDENTITY}" ]] \
  || fail "set PHONE_USE_SIGN_IDENTITY to a Developer ID Application identity"
[[ "${IDENTITY}" == "Developer ID Application:"* ]] \
  || fail "PHONE_USE_SIGN_IDENTITY must be a Developer ID Application identity"
[[ -n "${NOTARY_PROFILE}" ]] \
  || fail "set PHONE_USE_NOTARY_PROFILE to a notarytool keychain profile"
security find-identity -v -p codesigning | grep -F -- "\"${IDENTITY}\"" >/dev/null \
  || fail "the requested Developer ID identity is not available in the keychain"

case "${DMG}" in
  "${PROJECT_DIR}/dist/Phone-Use-${VERSION}.dmg") ;;
  *) fail "unexpected disk image path" ;;
esac

PHONE_USE_SIGN_IDENTITY="${IDENTITY}" "${SCRIPT_DIR}/package-app.sh"
PHONE_USE_REQUIRE_DISTRIBUTION=1 \
PHONE_USE_EXPECTED_ARCHS=arm64 \
  "${SCRIPT_DIR}/verify-package.sh" "${APP_DIR}"

rm -f "${SUBMISSION_ZIP}" "${WORK_DMG}" "${WORK_SHA256_FILE}"
rm -rf "${WORK_CASK_ROOT}"
rm -f "${LEGACY_DMG}" "${LEGACY_SHA256_FILE}"
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

PHONE_USE_REQUIRE_DISTRIBUTION=1 \
PHONE_USE_REQUIRE_NOTARIZATION=1 \
PHONE_USE_EXPECTED_ARCHS=arm64 \
  "${SCRIPT_DIR}/verify-package.sh" "${APP_DIR}"
codesign --verify --strict --verbose=2 "${WORK_DMG}"
hdiutil verify "${WORK_DMG}" >/dev/null
spctl --assess --type open --context context:primary-signature --verbose=4 "${WORK_DMG}"
DMG_SHA256=$(shasum -a 256 "${WORK_DMG}" | awk '{ print $1 }')
print -r -- "${DMG_SHA256}  ${DMG:t}" >"${WORK_SHA256_FILE}"
mkdir -p "${WORK_CASK:h}"
ln "${WORK_DMG}" "${WORK_CASK_ASSET}"
PHONE_USE_CASK_LOCAL=0 \
PHONE_USE_CASK_URL= \
  "${SCRIPT_DIR}/render-cask.sh" "${WORK_CASK_ASSET}" "${WORK_CASK}"
rm -f "${WORK_CASK_ASSET}"
mkdir -p "${FINAL_CASK:h}"
mv -f "${WORK_DMG}" "${DMG}"
mv -f "${WORK_SHA256_FILE}" "${SHA256_FILE}"
mv -f "${WORK_CASK}" "${FINAL_CASK}"

print "Release-ready disk image: ${DMG}"
print "Checksum: ${SHA256_FILE}"
print "Homebrew Cask: ${FINAL_CASK}"
