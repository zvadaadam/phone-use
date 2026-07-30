#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
API_PORT=18747
WDA_PORT=18100
BASE_URL="http://127.0.0.1:${API_PORT}"
WDA_URL="http://127.0.0.1:${WDA_PORT}"
TOKEN_FILE="${HOME}/Library/Application Support/Mirror Relay/token"
BROKER_EXECUTABLE="${MIRROR_RELAY_BROKER_EXECUTABLE:-${PROJECT_DIR}/native/.build/debug/mirror-relay}"
TEMP_DIR=$(mktemp -d /tmp/mirror-relay-wda-smoke.XXXXXX)
BROKER_PID=""

cleanup() {
  if [[ -n "${BROKER_PID}" ]]; then
    kill "${BROKER_PID}" 2>/dev/null || true
    wait "${BROKER_PID}" 2>/dev/null || true
  fi
  case "${TEMP_DIR}" in
    /tmp/mirror-relay-wda-smoke.*) rm -rf "${TEMP_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

for port in "${API_PORT}" "${WDA_PORT}"; do
  if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 "FAIL: test port ${port} is already in use"
    exit 1
  fi
done

swift build --package-path "${PROJECT_DIR}/native" >/dev/null

MIRROR_RELAY_PORT="${API_PORT}" \
MIRROR_RELAY_TRANSPORT="webdriveragent" \
MIRROR_RELAY_WDA_URL="${WDA_URL}" \
MIRROR_RELAY_WDA_XCODEBUILD="${PROJECT_DIR}/fixtures/fake-xcodebuild.mjs" \
MIRROR_RELAY_WDA_PROJECT="${PROJECT_DIR}/fixtures/MockWebDriverAgent.xcodeproj" \
MIRROR_RELAY_WDA_DEVICE_ID="mock-iphone" \
MIRROR_RELAY_WDA_REMOTE_PORT="${WDA_PORT}" \
MIRROR_RELAY_MOCK_WDA_PORT="${WDA_PORT}" \
MIRROR_RELAY_PUBLIC_DIR="${PROJECT_DIR}/public" \
  "${BROKER_EXECUTABLE}" \
  >"${TEMP_DIR}/broker.log" 2>&1 &
BROKER_PID=$!

for _ in {1..100}; do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

if [[ ! -f "${TOKEN_FILE}" ]]; then
  print -u2 "FAIL: broker did not create its local token"
  exit 1
fi
TOKEN=$(<"${TOKEN_FILE}")
AUTH=("Authorization: Bearer ${TOKEN}")

curl -fsS -X POST -H "${AUTH[1]}" "${BASE_URL}/api/session/open" \
  >"${TEMP_DIR}/open-1.json" &
open_pid_1=$!
curl -fsS -X POST -H "${AUTH[1]}" "${BASE_URL}/api/session/open" \
  >"${TEMP_DIR}/open-2.json" &
open_pid_2=$!
wait "${open_pid_1}"
wait "${open_pid_2}"
open_response=$(<"${TEMP_DIR}/open-1.json")
if [[ "${open_response}" != *'"transport":"webdriveragent"'* ]]; then
  print -u2 "FAIL: broker did not select the WebDriverAgent transport"
  exit 1
fi

curl -fsS \
  -H "${AUTH[1]}" \
  "${BASE_URL}/api/observe" \
  -o "${TEMP_DIR}/iphone.jpg"
if [[ "$(xxd -p -l 2 "${TEMP_DIR}/iphone.jpg")" != "ffd8" ]]; then
  print -u2 "FAIL: observation was not normalized to JPEG"
  exit 1
fi

source_response=$(curl -fsS \
  -H "${AUTH[1]}" \
  "${BASE_URL}/api/source")
if [[ "${source_response}" != *'"type":"XCUIElementTypeApplication"'* ]]; then
  print -u2 "FAIL: accessibility source was not relayed"
  exit 1
fi

curl -fsS \
  -X POST \
  -H "${AUTH[1]}" \
  -H "Content-Type: application/json" \
  --data '{"type":"tap","x":0.5,"y":0.5}' \
  "${BASE_URL}/api/act" \
  >/dev/null

action_state=$(curl -fsS "${WDA_URL}/test/state")
ACTION_STATE="${action_state}" node -e '
  const state = JSON.parse(process.env.ACTION_STATE);
  const tap = state.actions.find((action) => action.path.endsWith("/wda/tap"));
  if (!tap || tap.body.x !== 195 || tap.body.y !== 422) process.exit(1);
'

curl -fsS \
  -X POST \
  -H "${AUTH[1]}" \
  "${BASE_URL}/api/session/close" \
  >/dev/null

for _ in {1..100}; do
  if ! curl -fsS "${WDA_URL}/status" >/dev/null 2>&1; then
    break
  fi
  sleep 0.02
done
if curl -fsS "${WDA_URL}/status" >/dev/null 2>&1; then
  print -u2 "FAIL: closing the broker session did not stop its WDA runner"
  exit 1
fi

print "PASS: broker auto-started WDA, observed JPEG/source, mapped input, and stopped the runner"
