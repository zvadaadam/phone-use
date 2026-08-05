#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BASE_URL="http://127.0.0.1:8747"
TOKEN_FILE="${HOME}/Library/Application Support/Phone Use/token"
TEMP_DIR=$(mktemp -d /tmp/phone-use-device.XXXXXX)

cleanup() {
  case "${TEMP_DIR}" in
    /tmp/phone-use-device.*) rm -rf "${TEMP_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

STATUS_JSON=""
for _ in {1..40}; do
  STATUS_JSON=$("${PROJECT_DIR}/native/.build/release/phone-use" status)
  if STATUS_JSON="${STATUS_JSON}" node -e '
    const status = JSON.parse(process.env.STATUS_JSON);
    process.exit(
      status.phase === "streaming"
        && status.fps >= 8
        && status.frameAgeMs != null
        && status.frameAgeMs <= 2000
        && status.captureMode === "screenCaptureKit"
        ? 0 : 1,
    );
  '; then
    break
  fi
  sleep 0.25
done
STATUS_JSON="${STATUS_JSON}" node -e '
  const status = JSON.parse(process.env.STATUS_JSON);
  if (status.phase !== "streaming") {
    throw new Error(`expected streaming phase, received ${status.phase}`);
  }
  if (status.fps < 8) {
    throw new Error(`expected at least 8 fps, received ${status.fps}`);
  }
  if (status.frameAgeMs == null || status.frameAgeMs > 2000) {
    throw new Error(`expected a frame newer than 2s, received ${status.frameAgeMs}ms`);
  }
  if (status.captureMode !== "screenCaptureKit") {
    throw new Error(`expected ScreenCaptureKit mode, received ${status.captureMode}`);
  }
'

"${PROJECT_DIR}/native/.build/release/phone-use" \
  observe "${TEMP_DIR}/iphone.jpg" >/dev/null
WIDTH=$(sips -g pixelWidth "${TEMP_DIR}/iphone.jpg" | awk '/pixelWidth/ { print $2 }')
HEIGHT=$(sips -g pixelHeight "${TEMP_DIR}/iphone.jpg" | awk '/pixelHeight/ { print $2 }')
if (( WIDTH < 500 || HEIGHT < 1000 )); then
  print -u2 "FAIL: expected a full-resolution portrait frame, received ${WIDTH}x${HEIGHT}"
  exit 1
fi

if [[ ! -f "${TOKEN_FILE}" ]]; then
  print -u2 "FAIL: local API token is missing"
  exit 1
fi
TOKEN=$(<"${TOKEN_FILE}")
set +e
curl --max-time 3 -s \
  -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/stream.mjpeg" \
  -o "${TEMP_DIR}/stream.mjpeg"
CURL_STATUS=$?
set -e
if (( CURL_STATUS != 0 && CURL_STATUS != 28 )); then
  print -u2 "FAIL: MJPEG request exited with status ${CURL_STATUS}"
  exit 1
fi
FRAME_COUNT=$(rg -a -o -- '--frame' "${TEMP_DIR}/stream.mjpeg" | wc -l | tr -d ' ')
if (( FRAME_COUNT < 20 )); then
  print -u2 "FAIL: expected at least 20 MJPEG frames in 3s, received ${FRAME_COUNT}"
  exit 1
fi

print "PASS: live iPhone at ${WIDTH}x${HEIGHT}, ScreenCaptureKit >=8 fps, ${FRAME_COUNT} MJPEG frames in 3s"
