#!/bin/zsh
set -u

failures=0
wda_project="${MIRROR_RELAY_WDA_PROJECT:-${HOME}/Library/Application Support/Mirror Relay/WebDriverAgent/WebDriverAgent.xcodeproj}"

pass() {
  print "PASS  $1"
}

fail() {
  print "FAIL  $1"
  failures=$((failures + 1))
}

if xcodebuild -version >/dev/null 2>&1; then
  pass "$(xcodebuild -version | paste -sd ' ' -)"
else
  fail "Xcode is not installed or selected"
fi

if [[ -d "${wda_project}" ]]; then
  pass "WebDriverAgent project is installed"
else
  fail "WebDriverAgent project is missing; use Mirror Relay → Set Up iPhone Automation…"
fi

device_json=$(mktemp -t mirror-relay-devices).json
trap 'rm -f "${device_json}"' EXIT INT TERM
if xcrun devicectl list devices --json-output "${device_json}" >/dev/null 2>&1; then
  device_count=$(plutil -extract result.devices raw -o - "${device_json}" 2>/dev/null)
else
  device_count=0
fi

iphone_found=false
iphone_paired=false
for ((index = 0; index < ${device_count:-0}; index++)); do
  device_type=$(plutil \
    -extract "result.devices.${index}.hardwareProperties.deviceType" \
    raw -o - "${device_json}" 2>/dev/null)
  if [[ "${device_type:l}" != "iphone" ]]; then
    continue
  fi
  iphone_found=true
  pairing_state=$(plutil \
    -extract "result.devices.${index}.connectionProperties.pairingState" \
    raw -o - "${device_json}" 2>/dev/null)
  if [[ "${pairing_state:l}" == "paired" ]]; then
    iphone_paired=true
    udid=$(plutil \
      -extract "result.devices.${index}.hardwareProperties.udid" \
      raw -o - "${device_json}" 2>/dev/null)
    pass "Paired iPhone is available to Xcode (${udid:-unknown UDID})"
    break
  fi
done

if [[ "${iphone_found}" != true ]]; then
  fail "No real iPhone is visible to CoreDevice"
elif [[ "${iphone_paired}" != true ]]; then
  fail "The connected iPhone is unpaired; pair it in Xcode → Window → Devices and Simulators"
fi

identity_summary=$(security find-identity -v -p codesigning 2>/dev/null | tail -n 1)
identity_count=$(print -r -- "${identity_summary}" | awk '{print $1}')
if [[ "${identity_count:-0}" -gt 0 ]] 2>/dev/null; then
  pass "${identity_count} usable code-signing identity/identities"
else
  fail "No usable Apple code-signing identity is installed"
fi

wda_url="${MIRROR_RELAY_WDA_URL:-http://127.0.0.1:8100}"
if curl -fsS --max-time 2 "${wda_url}/status" 2>/dev/null \
  | rg -q '"ready"[[:space:]]*:[[:space:]]*true'; then
  pass "WebDriverAgent is ready at ${wda_url}"
else
  print "INFO  WebDriverAgent is stopped; Mirror Relay will start it on demand"
fi

if (( failures > 0 )); then
  print
  print "${failures} prerequisite(s) are still missing."
  exit 1
fi

print
print "WebDriverAgent prerequisites are ready."
