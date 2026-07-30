#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
API_PORT=18749
BASE_URL="http://127.0.0.1:${API_PORT}"
TOKEN_FILE="${HOME}/Library/Application Support/Mirror Relay/token"
TEMP_DIR=$(mktemp -d /tmp/mirror-relay-integration.XXXXXX)
BROKER_PID=""

cleanup() {
  if [[ -n "${BROKER_PID}" ]]; then
    kill "${BROKER_PID}" 2>/dev/null || true
    wait "${BROKER_PID}" 2>/dev/null || true
  fi
  case "${TEMP_DIR}" in
    /tmp/mirror-relay-integration.*) rm -rf "${TEMP_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

if lsof -nP -iTCP:"${API_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 "FAIL: test port ${API_PORT} is already in use"
  exit 1
fi

swift build --package-path "${PROJECT_DIR}/native" >/dev/null

MIRROR_RELAY_PORT="${API_PORT}" \
MIRROR_RELAY_PUBLIC_DIR="${PROJECT_DIR}/public" \
  "${PROJECT_DIR}/native/.build/debug/mirror-relay" \
  >"${TEMP_DIR}/broker.log" 2>&1 &
BROKER_PID=$!

for _ in {1..100}; do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

if ! curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
  print -u2 "FAIL: broker did not start"
  exit 1
fi
if [[ ! -f "${TOKEN_FILE}" ]]; then
  print -u2 "FAIL: broker did not create its local token"
  exit 1
fi
if [[ "$(stat -f '%Lp' "${TOKEN_FILE}")" != "600" ]]; then
  print -u2 "FAIL: local token permissions are not 0600"
  exit 1
fi

TOKEN=$(<"${TOKEN_FILE}")
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

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

assert_code 200 "${BASE_URL}/"
assert_code 401 "${BASE_URL}/api/status"
assert_code 401 "${BASE_URL}/api/status?token=${TOKEN}"
assert_code 200 -H "${AUTH_HEADER}" "${BASE_URL}/api/status"

bootstrap_json=$(curl -fsS \
  -X POST \
  -H "${AUTH_HEADER}" \
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
if ! rg -qi '^Set-Cookie: MirrorRelaySession=.*HttpOnly; SameSite=Strict;' \
  "${TEMP_DIR}/bootstrap.headers"; then
  print -u2 "FAIL: dashboard session cookie is not hardened"
  exit 1
fi
assert_code 401 "${BASE_URL}${bootstrap_path}"
assert_code 200 -b "${TEMP_DIR}/cookies.txt" "${BASE_URL}/api/status"
assert_code 403 \
  -X POST \
  -b "${TEMP_DIR}/cookies.txt" \
  -H "Origin: https://attacker.example" \
  "${BASE_URL}/api/session/close"
assert_code 400 \
  -X POST \
  -H "${AUTH_HEADER}" \
  -H "Content-Type: application/json" \
  --data '{"type":"tap","x":2,"y":0.5}' \
  "${BASE_URL}/api/act"

listener=$(lsof -nP -iTCP:"${API_PORT}" -sTCP:LISTEN | tail -n +2)
if [[ "${listener}" != *"127.0.0.1:${API_PORT}"* ]]; then
  print -u2 "FAIL: broker is not restricted to IPv4 loopback"
  exit 1
fi

print "PASS: authenticated loopback API, one-time dashboard session, origin checks, and validation"
