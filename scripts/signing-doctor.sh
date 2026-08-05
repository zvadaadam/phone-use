#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/signing-identity.sh"
INSTALLED_APP="/Applications/Phone Use.app"

REQUESTED_IDENTITY="${PHONE_USE_SIGN_IDENTITY:-}"
DEVELOPMENT_IDENTITY=$(
  phone_use_select_development_identity "${REQUESTED_IDENTITY}"
)

if [[ -z "${DEVELOPMENT_IDENTITY}" ]]; then
  print -u2 "FAIL: no stable development signing identity is installed."
  print -u2 ""
  print -u2 "Install Apple Development through Xcode, or create a local identity:"
  print -u2 "  1. Keychain Access > Certificate Assistant > Create a Certificate"
  print -u2 "  2. Name: ${PHONE_USE_LOCAL_SIGN_IDENTITY}"
  print -u2 "  3. Identity Type: Self-Signed Root; Certificate Type: Code Signing"
  print -u2 "  4. Run npm run signing:doctor again"
  exit 1
fi

print "PASS: stable development identity is available"
DEVELOPMENT_IDENTITY_NAME=$(phone_use_identity_name_for_hash "${DEVELOPMENT_IDENTITY}")
print "Pinned identity: ${DEVELOPMENT_IDENTITY_NAME} (${DEVELOPMENT_IDENTITY})"
print "Pin file: ${PHONE_USE_SIGNING_PIN_FILE}"
print "package:dev will keep using this exact certificate."
if [[ "${DEVELOPMENT_IDENTITY_NAME}" == "${PHONE_USE_LOCAL_SIGN_IDENTITY}" \
    || "${DEVELOPMENT_IDENTITY_NAME}" == "${PHONE_USE_LEGACY_LOCAL_SIGN_IDENTITY}" ]]; then
  print "Channel: local-only self-signed development (permission persistence; not distribution)"
fi

if [[ -d "${INSTALLED_APP}" ]]; then
  INSTALLED_SIGNATURE=$(codesign -dv --verbose=4 "${INSTALLED_APP}" 2>&1)
  if [[ "${INSTALLED_SIGNATURE}" == *"Signature=adhoc"* ]]; then
    print "WARNING: the installed Phone Use is still ad-hoc signed."
    print "Build with npm run package:dev before replacing it."
  else
    INSTALLED_HASH=$(phone_use_signature_leaf_hash "${INSTALLED_APP}")
    if [[ "${INSTALLED_HASH:u}" != "${DEVELOPMENT_IDENTITY:u}" ]]; then
      print -u2 "FAIL: installed Phone Use uses a different signing certificate (${INSTALLED_HASH:u})."
      print -u2 "The next package:dev build will use the pinned certificate (${DEVELOPMENT_IDENTITY:u})."
      print -u2 "Install a package:dev build and grant permissions once for the pinned identity."
      exit 1
    fi
    print "Installed Phone Use matches the pinned stable signature."
    codesign -d -r- "${INSTALLED_APP}" 2>&1 | sed -n '/designated =>/p'
  fi
fi

print "Project: ${PROJECT_DIR}"
