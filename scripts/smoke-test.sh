#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BASE_URL="http://127.0.0.1:8747"
TOKEN_FILE="${HOME}/Library/Application Support/Mirror Relay/token"

"${SCRIPT_DIR}/mirror-relayctl" status >/dev/null

if [[ ! -f "${TOKEN_FILE}" ]]; then
  print -u2 "FAIL: Mirror Relay did not create its local token"
  exit 1
fi
if [[ "$(stat -f '%Lp' "${TOKEN_FILE}")" != "600" ]]; then
  print -u2 "FAIL: local token permissions are not 0600"
  exit 1
fi

TOKEN=$(<"${TOKEN_FILE}")

assert_code() {
  local expected="$1"
  shift
  local actual
  actual=$(curl -sS -o /dev/null -w '%{http_code}' "$@")
  if [[ "${actual}" != "${expected}" ]]; then
    print -u2 "FAIL: expected HTTP ${expected}, received ${actual}"
    exit 1
  fi
}

assert_code 200 "${BASE_URL}/health"
assert_code 200 "${BASE_URL}/"
assert_code 401 "${BASE_URL}/api/status"
assert_code 401 -H "Authorization: Bearer invalid" "${BASE_URL}/api/status"
assert_code 200 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/api/status"
assert_code 400 \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"type":"tap","x":2,"y":0.5}' \
  "${BASE_URL}/api/act"

listener=$(lsof -nP -iTCP:8747 -sTCP:LISTEN | tail -n +2)
if [[ "${listener}" != *"127.0.0.1:8747"* ]]; then
  print -u2 "FAIL: broker is not restricted to IPv4 loopback"
  exit 1
fi

print "PASS: Mirror Relay local API, authentication, validation, and token permissions"
