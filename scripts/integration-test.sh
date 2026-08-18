#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
API_PORT=18749
BASE_URL="http://127.0.0.1:${API_PORT}"
TOKEN_FILE="${HOME}/Library/Application Support/Phone Use/token"
TEMP_DIR=$(mktemp -d /tmp/phone-use-integration.XXXXXX)
BROKER_PID=""

cleanup() {
  if [[ -n "${BROKER_PID}" ]]; then
    kill "${BROKER_PID}" 2>/dev/null || true
    wait "${BROKER_PID}" 2>/dev/null || true
  fi
  case "${TEMP_DIR}" in
    /tmp/phone-use-integration.*) rm -rf "${TEMP_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

if lsof -nP -iTCP:"${API_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 "FAIL: test port ${API_PORT} is already in use"
  exit 1
fi

swift build --package-path "${PROJECT_DIR}/native" >/dev/null
env PHONE_USE_PORT="${API_PORT}" PHONE_USE_PUBLIC_DIR="${PROJECT_DIR}/public" "${PROJECT_DIR}/native/.build/debug/phone-use-app" >"${TEMP_DIR}/broker.log" 2>&1 &
BROKER_PID=$!

for _ in {1..100}; do
  curl -sS "${BASE_URL}/" >/dev/null 2>&1 && break
  sleep 0.05
done
if ! curl -sS "${BASE_URL}/" >/dev/null 2>&1; then
  print -u2 "FAIL: broker did not start"
  exit 1
fi
[[ -f "${TOKEN_FILE}" ]] || { print -u2 "FAIL: broker did not create token"; exit 1; }
[[ "$(stat -f '%Lp' "${TOKEN_FILE}")" == "600" ]] || { print -u2 "FAIL: token permissions are not 0600"; exit 1; }

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
assert_code 401 "${BASE_URL}/"
assert_code 200 -H "${AUTH_HEADER}" "${BASE_URL}/"
assert_code 403 -H "Host: rebinding.attacker.example" "${BASE_URL}/"
assert_code 401 "${BASE_URL}/api/status"
assert_code 401 "${BASE_URL}/api/status?token=${TOKEN}"
assert_code 401 "${BASE_URL}/auth/dashboard?bootstrap=first&bootstrap=second"
assert_code 200 -H "${AUTH_HEADER}" "${BASE_URL}/api/status"

status_json=$(curl -fsS -H "${AUTH_HEADER}" "${BASE_URL}/api/status")
STATUS_JSON="${status_json}" node -e '
  const status = JSON.parse(process.env.STATUS_JSON);
  if (status.product !== "phone-use") throw new Error("unexpected product");
  if (status.protocolVersion !== 4) throw new Error("unexpected protocol version");
  if (status.transport !== "ios27-device-hub") throw new Error("unexpected transport");
  if (status.phase !== "unavailable") throw new Error("backend must fail closed");
  if (status.proof !== "unimplemented") throw new Error("proof state is dishonest");
  if (status.requirements?.minimumIOSVersion !== "27.0") {
    throw new Error("missing iOS 27 requirement");
  }
  if (status.internetRelayAvailable !== false) {
    throw new Error("internet relay must not be claimed");
  }
  for (const name of ["pointer", "keyboard", "shortcuts"]) {
    if (status.controlCapabilities?.[name] !== false) {
      throw new Error(name + " must remain disabled");
    }
  }
  const expected = [
    "controlCapabilities", "internetRelayAvailable", "logs",
    "macFocusPolicy", "message", "phase", "product", "proof",
    "protocolVersion", "requirements", "transport", "version",
  ];
  if (Object.keys(status).sort().join() !== expected.sort().join()) {
    throw new Error("status contract contains unexpected fields");
  }
'

assert_code 503 -H "${AUTH_HEADER}" "${BASE_URL}/api/observe"
assert_code 409 -X POST -H "${AUTH_HEADER}" "${BASE_URL}/api/device/connect"
assert_code 200 -X POST -H "${AUTH_HEADER}" "${BASE_URL}/api/device/disconnect"
assert_code 400 -X POST -H "${AUTH_HEADER}" -H "Content-Type: application/json" --data '{"type":"tap","x":2,"y":0.5}' "${BASE_URL}/api/actions"
assert_code 409 -X POST -H "${AUTH_HEADER}" -H "Content-Type: application/json" --data '{"type":"tap","x":0.5,"y":0.5,"expectedFrameToken":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' "${BASE_URL}/api/actions"

bootstrap_json=$(curl -fsS -X POST -H "${AUTH_HEADER}" "${BASE_URL}/api/dashboard/bootstrap")
bootstrap_path=$(BOOTSTRAP_JSON="${bootstrap_json}" node -e '
  const value = JSON.parse(process.env.BOOTSTRAP_JSON);
  if (typeof value.path !== "string") process.exit(1);
  process.stdout.write(value.path);
')
assert_code 303 -D "${TEMP_DIR}/bootstrap.headers" -c "${TEMP_DIR}/cookies.txt" "${BASE_URL}${bootstrap_path}"
rg -qi '^Set-Cookie: PhoneUseSession=.*HttpOnly; SameSite=Strict;' "${TEMP_DIR}/bootstrap.headers" || { print -u2 "FAIL: dashboard cookie is not hardened"; exit 1; }
assert_code 401 "${BASE_URL}${bootstrap_path}"
assert_code 200 -b "${TEMP_DIR}/cookies.txt" "${BASE_URL}/api/status"
assert_code 403 -X POST -b "${TEMP_DIR}/cookies.txt" -H "Origin: https://attacker.example" "${BASE_URL}/api/device/disconnect"

listener=$(lsof -nP -iTCP:"${API_PORT}" -sTCP:LISTEN | tail -n +2)
[[ "${listener}" == *"127.0.0.1:${API_PORT}"* ]] || { print -u2 "FAIL: broker is not restricted to IPv4 loopback"; exit 1; }

print "PASS: Device Hub-only API is authenticated, explicit, and fail-closed"
