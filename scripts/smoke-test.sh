#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BASE_URL="http://127.0.0.1:8747"
TOKEN_FILE="${HOME}/Library/Application Support/Phone Use/token"
EXPECTED_VERSION=$(/usr/bin/plutil -extract version raw -o - "${PROJECT_DIR}/package.json")

"${SCRIPT_DIR}/phone-use" status >/dev/null
[[ "$("${SCRIPT_DIR}/phone-use" version)" == "Phone Use ${EXPECTED_VERSION}" ]] || { print -u2 "FAIL: installed CLI version mismatch"; exit 1; }
[[ -f "${TOKEN_FILE}" ]] || { print -u2 "FAIL: local token is missing"; exit 1; }
[[ "$(stat -f '%Lp' "${TOKEN_FILE}")" == "600" ]] || { print -u2 "FAIL: local token permissions are not 0600"; exit 1; }

TOKEN=$(<"${TOKEN_FILE}")
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

assert_code() {
  local expected="$1"
  shift
  local actual
  actual=$(curl -sS -o /dev/null -w '%{http_code}' "$@")
  [[ "${actual}" == "${expected}" ]] || { print -u2 "FAIL: expected HTTP ${expected}, received ${actual}"; exit 1; }
}

assert_code 401 "${BASE_URL}/health"
assert_code 200 -H "${AUTH_HEADER}" "${BASE_URL}/health"
assert_code 200 -H "${AUTH_HEADER}" "${BASE_URL}/api/status"
assert_code 503 -H "${AUTH_HEADER}" "${BASE_URL}/api/observe"
assert_code 409 -X POST -H "${AUTH_HEADER}" "${BASE_URL}/api/device/connect"

status_json=$(curl -fsS -H "${AUTH_HEADER}" "${BASE_URL}/api/status")
STATUS_JSON="${status_json}" node -e '
  const status = JSON.parse(process.env.STATUS_JSON);
  if (status.transport !== "ios27-device-hub") throw new Error("wrong transport");
  if (status.proof !== "unimplemented") throw new Error("unexpected proof state");
'

listener=$(lsof -nP -iTCP:8747 -sTCP:LISTEN | tail -n +2)
[[ "${listener}" == *"127.0.0.1:8747"* ]] || { print -u2 "FAIL: broker is not restricted to IPv4 loopback"; exit 1; }

print "PASS: packaged Phone Use exposes only the fail-closed Device Hub API"
