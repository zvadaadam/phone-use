#!/bin/zsh
set -euo pipefail

CLI="/Applications/Phone Use.app/Contents/Helpers/phone-use"
MIRRORING_BUNDLE_ID="com.apple.ScreenContinuity"
TEMP_DIR=$(mktemp -d /tmp/phone-use-focus.XXXXXX)
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
    /tmp/phone-use-focus.*) rm -rf "${TEMP_DIR}" ;;
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

observe_with_retry() {
  local output_file="$1"
  local observation
  for _ in {1..30}; do
    if observation=$("${CLI}" observe "${output_file}" 2>/dev/null); then
      print -r -- "${observation}"
      return 0
    fi
    sleep 0.1
  done
  print -u2 "FAIL: no fresh iPhone frame became available"
  return 1
}

if [[ ! -x "${CLI}" ]]; then
  print -u2 "FAIL: install Phone Use in /Applications first"
  exit 1
fi

BEFORE_INFO=$(frontmost_info)
BEFORE_PID=$(print -r -- "${BEFORE_INFO}" | cut -f1)
BEFORE_BUNDLE=$(print -r -- "${BEFORE_INFO}" | cut -f2)
if [[ -z "${BEFORE_PID}" ]]; then
  print -u2 "FAIL: could not identify the frontmost Mac app"
  exit 1
fi
if [[ "${BEFORE_BUNDLE}" == "${MIRRORING_BUNDLE_ID}" ]]; then
  print -u2 "FAIL: make the browser or another Mac app frontmost before running this test"
  exit 1
fi

BEFORE_OBSERVE=$(observe_with_retry "${TEMP_DIR}/before.jpg")
BEFORE_TOKEN=$(print -r -- "${BEFORE_OBSERVE}" \
  | sed -n 's/.* token \([0-9a-f]*\) to .*/\1/p')
[[ ${#BEFORE_TOKEN} == 64 ]] || {
  print -u2 "FAIL: observe did not return a valid frame token"
  exit 1
}

sample_frontmost_processes &
SAMPLER_PID=$!
for _ in {1..100}; do
  [[ -s "${SAMPLE_FILE}" ]] && break
  sleep 0.01
done

set +e
RESULT=$("${CLI}" "${COMMAND_ARGS[@]}" 2>&1)
COMMAND_STATUS=$?
set -e
touch "${STOP_FILE}"
wait "${SAMPLER_PID}"
SAMPLER_PID=""

if (( COMMAND_STATUS == 0 )); then
  print -u2 "FAIL: ${COMMAND_LABEL} was accepted while another Mac app was frontmost"
  exit 1
fi
if [[ "${RESULT}" != *"Phone Use never changes Mac focus"* ]]; then
  print -u2 "FAIL: background refusal did not explain the focus invariant"
  print -u2 -- "${RESULT}"
  exit 1
fi

AFTER_OBSERVE=$(observe_with_retry "${TEMP_DIR}/after.jpg")
AFTER_TOKEN=$(print -r -- "${AFTER_OBSERVE}" \
  | sed -n 's/.* token \([0-9a-f]*\) to .*/\1/p')
BEFORE_TOKEN="${BEFORE_TOKEN}" AFTER_TOKEN="${AFTER_TOKEN}" node -e '
  const before = process.env.BEFORE_TOKEN;
  const after = process.env.AFTER_TOKEN;
  if (before.length !== 64 || after.length !== 64) {
    throw new Error("observe did not return two valid frame tokens");
  }
  const distance = [...before].reduce(
    (sum, digit, index) =>
      sum + Math.abs(parseInt(digit, 16) - parseInt(after[index], 16)),
    0,
  );
  if (distance > 12) {
    throw new Error(`phone changed after a refused command (distance ${distance})`);
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
  print -u2 "FAIL: foreground changed during refused control: ${FOREIGN_SAMPLE}"
  exit 1
fi

AFTER_INFO=$(frontmost_info)
AFTER_PID=$(print -r -- "${AFTER_INFO}" | cut -f1)
if [[ "${AFTER_PID}" != "${BEFORE_PID}" ]]; then
  print -u2 "FAIL: focus moved from PID ${BEFORE_PID} (${BEFORE_BUNDLE}) to PID ${AFTER_PID}"
  exit 1
fi

print "PASS: ${COMMAND_LABEL} failed closed and all ${SAMPLE_COUNT} foreground samples stayed on PID ${BEFORE_PID} (${BEFORE_BUNDLE})"
