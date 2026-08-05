#!/bin/zsh
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  print -u2 "Usage: render-cask.sh <Phone-Use-version.dmg> [output.rb]"
  exit 2
fi

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DMG="${1:A}"
OUTPUT="${2:-${PROJECT_DIR}/dist/homebrew/Casks/phone-use.rb}"
OUTPUT="${OUTPUT:A}"
VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")
EXPECTED_ASSET="Phone-Use-${VERSION}.dmg"
DEFAULT_URL="https://github.com/zvadaadam/homebrew-tap/releases/download/phone-use-v${VERSION}/${EXPECTED_ASSET}"
CASK_URL_OVERRIDE="${PHONE_USE_CASK_URL:-}"
LOCAL_CASK="${PHONE_USE_CASK_LOCAL:-0}"

fail() {
  print -u2 "Cask generation failed: $1"
  exit 1
}

[[ -f "${DMG}" ]] || fail "disk image does not exist at ${DMG}"
[[ "${DMG:t}" == "${EXPECTED_ASSET}" ]] \
  || fail "expected ${EXPECTED_ASSET}; found ${DMG:t}"
case "${LOCAL_CASK}" in
  0)
    CASK_URL="${CASK_URL_OVERRIDE:-${DEFAULT_URL}}"
    [[ "${CASK_URL}" == https://* ]] \
      || fail "PHONE_USE_CASK_URL must use https://"
    ;;
  1)
    [[ -z "${CASK_URL_OVERRIDE}" ]] \
      || fail "PHONE_USE_CASK_LOCAL and PHONE_USE_CASK_URL are mutually exclusive"
    CASK_URL=$(node -e \
      'process.stdout.write(require("node:url").pathToFileURL(process.argv[1]).href)' \
      "${DMG}")
    ;;
  *) fail "PHONE_USE_CASK_LOCAL must be 0 or 1" ;;
esac
[[ "${CASK_URL}" != *'"'* && "${CASK_URL}" != *$'\\'* \
    && "${CASK_URL}" != *'#'* \
    && "${CASK_URL}" != *$'\n'* && "${CASK_URL}" != *$'\r'* ]] \
  || fail "PHONE_USE_CASK_URL contains unsafe characters"

DMG_SHA256=$(shasum -a 256 "${DMG}" | awk '{ print $1 }')
mkdir -p "${OUTPUT:h}"
TEMPORARY_OUTPUT=$(mktemp "${OUTPUT:h}/.phone-use.rb.XXXXXX")

cleanup() {
  rm -f "${TEMPORARY_OUTPUT}"
}
trap cleanup EXIT INT TERM

cat >"${TEMPORARY_OUTPUT}" <<EOF
# typed: strict
# frozen_string_literal: true

cask "phone-use" do
  version "${VERSION}"
  sha256 "${DMG_SHA256}"

  url "${CASK_URL}"
  name "Phone Use"
  desc "Local agent bridge for Apple iPhone Mirroring"
  homepage "https://github.com/zvadaadam/homebrew-tap"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Phone Use.app"
  binary "#{appdir}/Phone Use.app/Contents/Helpers/phone-use", target: "phone-use"

  uninstall quit: "com.adamzvada.mirrorrelay"

  zap trash: [
    "~/Library/Application Support/Mirror Relay",
    "~/Library/Application Support/Phone Use",
    "~/Library/Preferences/com.adamzvada.mirrorrelay.plist",
  ]
end
EOF

chmod 644 "${TEMPORARY_OUTPUT}"
mv -f "${TEMPORARY_OUTPUT}" "${OUTPUT}"
print "Homebrew Cask: ${OUTPUT}"
