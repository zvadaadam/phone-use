#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BASE_URL="http://127.0.0.1:8747"
TOKEN_FILE="${HOME}/Library/Application Support/Mirror Relay/token"
TEMP_DIR=$(mktemp -d /tmp/mirror-relay-smoke.XXXXXX)
EXPECTED_VERSION=$(node -p "require('${PROJECT_DIR}/package.json').version")

cleanup() {
  case "${TEMP_DIR}" in
    /tmp/mirror-relay-smoke.*) rm -rf "${TEMP_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

"${SCRIPT_DIR}/mirror-relayctl" status >/dev/null
if [[ "$("${SCRIPT_DIR}/mirror-relayctl" version)" != "Mirror Relay ${EXPECTED_VERSION}" ]]; then
  print -u2 "FAIL: installed CLI is not version ${EXPECTED_VERSION}"
  exit 1
fi

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
assert_code 401 "${BASE_URL}/api/status?token=${TOKEN}"
assert_code 401 -H "Authorization: Bearer invalid" "${BASE_URL}/api/status"
assert_code 200 -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}/api/status"
assert_code 400 \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"type":"tap","x":2,"y":0.5}' \
  "${BASE_URL}/api/act"

bootstrap_json=$(curl -fsS \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/api/dashboard/bootstrap")
bootstrap_path=$(BOOTSTRAP_JSON="${bootstrap_json}" node -e '
  const value = JSON.parse(process.env.BOOTSTRAP_JSON);
  if (typeof value.path !== "string") process.exit(1);
  process.stdout.write(value.path);
')
assert_code 303 \
  -D "${TEMP_DIR}/bootstrap.headers" \
  -c "${TEMP_DIR}/cookies.txt" \
  "${BASE_URL}${bootstrap_path}"
assert_code 401 "${BASE_URL}${bootstrap_path}"
assert_code 200 -b "${TEMP_DIR}/cookies.txt" "${BASE_URL}/api/status"

listener=$(lsof -nP -iTCP:8747 -sTCP:LISTEN | tail -n +2)
if [[ "${listener}" != *"127.0.0.1:8747"* ]]; then
  print -u2 "FAIL: broker is not restricted to IPv4 loopback"
  exit 1
fi

print "PASS: Mirror Relay local API, authentication, validation, and token permissions"
