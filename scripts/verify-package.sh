#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/signing-identity.sh"
APP_DIR="${1:-${PROJECT_DIR}/dist/Phone Use.app}"
REQUIRE_DISTRIBUTION="${PHONE_USE_REQUIRE_DISTRIBUTION:-0}"
REQUIRE_NOTARIZATION="${PHONE_USE_REQUIRE_NOTARIZATION:-0}"
REQUIRE_STABLE_SIGNING="${PHONE_USE_REQUIRE_STABLE_SIGNING:-0}"
EXPECTED_SIGNING_HASH="${PHONE_USE_EXPECTED_SIGNING_HASH:-}"
EXPECTED_VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")
EXPECTED_BUNDLE_ID=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleIdentifier" \
  "${PROJECT_DIR}/native/App/Info.plist")
MAIN_EXECUTABLE="${APP_DIR}/Contents/MacOS/Phone Use"
HELPER_EXECUTABLE="${APP_DIR}/Contents/Helpers/phone-use"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

fail() {
  print -u2 "Package verification failed: $1"
  exit 1
}

[[ -d "${APP_DIR}" ]] || fail "app bundle does not exist at ${APP_DIR}"
[[ -x "${MAIN_EXECUTABLE}" ]] || fail "main executable is missing"
[[ -x "${HELPER_EXECUTABLE}" ]] || fail "CLI helper is missing from Contents/Helpers"
[[ ! -e "${APP_DIR}/Contents/Resources/bin" ]] \
  || fail "executable code must not be stored under Contents/Resources"

ACTUAL_VERSION=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleShortVersionString" \
  "${APP_DIR}/Contents/Info.plist")
ACTUAL_BUNDLE_ID=$(/usr/libexec/PlistBuddy \
  -c "Print :CFBundleIdentifier" \
  "${APP_DIR}/Contents/Info.plist")
[[ "${ACTUAL_VERSION}" == "${EXPECTED_VERSION}" ]] \
  || fail "version is ${ACTUAL_VERSION}; expected ${EXPECTED_VERSION}"
[[ "${ACTUAL_BUNDLE_ID}" == "${EXPECTED_BUNDLE_ID}" ]] \
  || fail "bundle identifier is ${ACTUAL_BUNDLE_ID}; expected ${EXPECTED_BUNDLE_ID}"

file "${MAIN_EXECUTABLE}" | grep -q "Mach-O" || fail "main executable is not Mach-O"
file "${HELPER_EXECUTABLE}" | grep -q "Mach-O" || fail "CLI helper is not Mach-O"
otool -L "${MAIN_EXECUTABLE}" | grep -q "ScreenCaptureKit" \
  || fail "main executable does not link ScreenCaptureKit"
if otool -L "${HELPER_EXECUTABLE}" | grep -Eq "ScreenCaptureKit|ApplicationServices"; then
  fail "CLI helper unexpectedly links capture or input frameworks"
fi

while IFS= read -r -d '' resource; do
  if file -b "${resource}" | grep -q "^Mach-O"; then
    fail "Mach-O executable found in Resources: ${resource}"
  fi
done < <(find "${RESOURCES_DIR}" -type f -print0)

codesign --verify --strict --verbose=2 "${HELPER_EXECUTABLE}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
APP_SIGNATURE=$(codesign -dv --verbose=4 "${APP_DIR}" 2>&1)
HELPER_SIGNATURE=$(codesign -dv --verbose=4 "${HELPER_EXECUTABLE}" 2>&1)
[[ "${APP_SIGNATURE}" == *"runtime"* ]] || fail "app is missing hardened runtime"
[[ "${HELPER_SIGNATURE}" == *"runtime"* ]] || fail "CLI helper is missing hardened runtime"

if [[ "${REQUIRE_STABLE_SIGNING}" == "1" ]]; then
  if [[ "${APP_SIGNATURE}" == *"Authority=Apple Development:"* \
      || "${APP_SIGNATURE}" == *"Authority=Developer ID Application:"* ]]; then
    if [[ "${HELPER_SIGNATURE}" != *"Authority=Apple Development:"* \
        && "${HELPER_SIGNATURE}" != *"Authority=Developer ID Application:"* ]]; then
      fail "app and CLI helper do not use the same Apple-backed signing channel"
    fi
  elif [[ "${APP_SIGNATURE}" == *"Authority=${PHONE_USE_LOCAL_SIGN_IDENTITY}"* \
      && "${HELPER_SIGNATURE}" == *"Authority=${PHONE_USE_LOCAL_SIGN_IDENTITY}"* \
      || "${APP_SIGNATURE}" == *"Authority=${PHONE_USE_LEGACY_LOCAL_SIGN_IDENTITY}"* \
      && "${HELPER_SIGNATURE}" == *"Authority=${PHONE_USE_LEGACY_LOCAL_SIGN_IDENTITY}"* ]]; then
    :
  else
    fail "app is not signed with a supported stable development identity"
  fi
  APP_LEAF_HASH="$(phone_use_signature_leaf_hash "${APP_DIR}")"
  HELPER_LEAF_HASH="$(phone_use_signature_leaf_hash "${HELPER_EXECUTABLE}")"
  APP_LEAF_HASH="${APP_LEAF_HASH:u}"
  HELPER_LEAF_HASH="${HELPER_LEAF_HASH:u}"
  [[ -n "${APP_LEAF_HASH}" && "${APP_LEAF_HASH}" == "${HELPER_LEAF_HASH}" ]] \
    || fail "app and CLI helper do not share one stable signing certificate"
  if [[ -n "${EXPECTED_SIGNING_HASH}" ]]; then
    [[ "${APP_LEAF_HASH}" == "${EXPECTED_SIGNING_HASH:u}" ]] \
      || fail "package signer does not match the selected certificate"
  fi
fi

if [[ "${REQUIRE_DISTRIBUTION}" == "1" ]]; then
  [[ "${APP_SIGNATURE}" == *"Authority=Developer ID Application:"* ]] \
    || fail "app is not signed with Developer ID Application"
  [[ "${HELPER_SIGNATURE}" == *"Authority=Developer ID Application:"* ]] \
    || fail "CLI helper is not signed with Developer ID Application"
  APP_TEAM=$(print -r -- "${APP_SIGNATURE}" | sed -n 's/^TeamIdentifier=//p')
  HELPER_TEAM=$(print -r -- "${HELPER_SIGNATURE}" | sed -n 's/^TeamIdentifier=//p')
  [[ -n "${APP_TEAM}" && "${APP_TEAM}" == "${HELPER_TEAM}" ]] \
    || fail "app and CLI helper do not share one signing team"
fi

if [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
  xcrun stapler validate "${APP_DIR}"
  spctl --assess --type execute --verbose=4 "${APP_DIR}"
fi

MAIN_ARCHS=$(lipo -archs "${MAIN_EXECUTABLE}")
HELPER_ARCHS=$(lipo -archs "${HELPER_EXECUTABLE}")
[[ "${MAIN_ARCHS}" == "${HELPER_ARCHS}" ]] \
  || fail "app architectures (${MAIN_ARCHS}) differ from CLI helper (${HELPER_ARCHS})"
if [[ -n "${PHONE_USE_EXPECTED_ARCHS:-}" ]]; then
  for expected_arch in ${(z)PHONE_USE_EXPECTED_ARCHS}; do
    [[ " ${MAIN_ARCHS} " == *" ${expected_arch} "* ]] \
      || fail "packaged binaries are missing ${expected_arch}; found ${MAIN_ARCHS}"
  done
fi

print "PASS: Phone Use ${ACTUAL_VERSION} package layout, protocol helper, and signatures"
