#!/bin/zsh
set -euo pipefail

CLI="/Applications/Mirror Relay.app/Contents/Helpers/mirror-relay"
MIRRORING_BUNDLE_ID="com.apple.ScreenContinuity"
TEMP_DIR=$(mktemp -d /tmp/mirror-relay-focus.XXXXXX)
SAMPLE_FILE="${TEMP_DIR}/frontmost.tsv"
STOP_FILE="${TEMP_DIR}/stop"
SAMPLER_PID=""
if (( $# == 0 )); then
  COMMAND_ARGS=(home)
else
  COMMAND_ARGS=("$@")
fi
COMMAND_LABEL="${(j: :)COMMAND_ARGS}"

cleanup() {
  if [[ -n "${SAMPLER_PID}" ]]; then
    kill "${SAMPLER_PID}" 2>/dev/null || true
    wait "${SAMPLER_PID}" 2>/dev/null || true
  fi
  case "${TEMP_DIR}" in
    /tmp/mirror-relay-focus.*) rm -rf "${TEMP_DIR}" ;;
  esac
}
trap cleanup EXIT INT TERM

frontmost_info() {
  /usr/bin/swift -e '
    import AppKit
    guard let app = NSWorkspace.shared.frontmostApplication else { exit(1) }
    print("\(app.processIdentifier)\t\(app.bundleIdentifier ?? "")")
  '
}

process_id_from() {
  print -r -- "$1" | cut -f1
}

bundle_id_from() {
  print -r -- "$1" | cut -f2
}

sample_frontmost_processes() {
  /usr/bin/swift -e '
    import AppKit
    import Darwin
    import Foundation
    setbuf(stdout, nil)
    let stopPath = CommandLine.arguments[1]
    while !FileManager.default.fileExists(atPath: stopPath) {
      if let app = NSWorkspace.shared.frontmostApplication {
        print(
          "\(Date().timeIntervalSince1970)\t"
            + "\(app.processIdentifier)\t\(app.bundleIdentifier ?? "")"
        )
      }
      usleep(10_000)
    }
  ' "${STOP_FILE}" >>"${SAMPLE_FILE}"
}

if [[ ! -x "${CLI}" ]]; then
  print -u2 "FAIL: install Mirror Relay in /Applications first"
  exit 1
fi

BEFORE_INFO=$(frontmost_info)
BEFORE_PID=$(process_id_from "${BEFORE_INFO}")
BEFORE_BUNDLE=$(bundle_id_from "${BEFORE_INFO}")
if [[ -z "${BEFORE_PID}" ]]; then
  print -u2 "FAIL: could not identify the frontmost Mac app"
  exit 1
fi
if [[ "${BEFORE_BUNDLE}" == "${MIRRORING_BUNDLE_ID}" ]]; then
  print -u2 "FAIL: make the browser or another Mac app frontmost before running this test"
  exit 1
fi

sample_frontmost_processes &
SAMPLER_PID=$!
for _ in {1..100}; do
  [[ -s "${SAMPLE_FILE}" ]] && break
  sleep 0.01
done
set +e
RESULT=$("${CLI}" "${COMMAND_ARGS[@]}")
COMMAND_STATUS=$?
set -e
touch "${STOP_FILE}"
wait "${SAMPLER_PID}"
SAMPLER_PID=""
if (( COMMAND_STATUS != 0 )); then
  print -u2 "FAIL: ${COMMAND_LABEL} exited with status ${COMMAND_STATUS}"
  exit "${COMMAND_STATUS}"
fi
RESULT_JSON="${RESULT}" node -e '
  const result = JSON.parse(process.env.RESULT_JSON);
  if (result.success !== true) {
    throw new Error("Control command did not succeed");
  }
'

SAMPLE_COUNT=$(wc -l <"${SAMPLE_FILE}" | tr -d ' ')
if (( SAMPLE_COUNT < 2 )); then
  print -u2 "FAIL: foreground sampler captured only ${SAMPLE_COUNT} samples"
  exit 1
fi
FOREIGN_SAMPLE=$(awk -F '\t' -v expected="${BEFORE_PID}" \
  '$2 != expected { print; exit }' "${SAMPLE_FILE}")
if [[ -n "${FOREIGN_SAMPLE}" ]]; then
  print -u2 "FAIL: foreground changed during control: ${FOREIGN_SAMPLE}"
  exit 1
fi

AFTER_INFO=$(frontmost_info)
AFTER_PID=$(process_id_from "${AFTER_INFO}")
if [[ "${AFTER_PID}" != "${BEFORE_PID}" ]]; then
  print -u2 "FAIL: focus moved from PID ${BEFORE_PID} (${BEFORE_BUNDLE}) to PID ${AFTER_PID}"
  exit 1
fi

print "PASS: ${COMMAND_LABEL} reached the iPhone while all ${SAMPLE_COUNT} foreground samples stayed on PID ${BEFORE_PID} (${BEFORE_BUNDLE})"
