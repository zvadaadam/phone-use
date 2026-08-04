#!/bin/zsh

MIRROR_RELAY_LOCAL_SIGN_IDENTITY="${MIRROR_RELAY_LOCAL_SIGN_IDENTITY:-Mirror Relay Local Development}"
MIRROR_RELAY_SIGNING_STATE_DIR="${MIRROR_RELAY_SIGNING_STATE_DIR:-${PROJECT_DIR}/.mirror-relay}"
MIRROR_RELAY_SIGNING_PIN_FILE="${MIRROR_RELAY_SIGNING_PIN_FILE:-${MIRROR_RELAY_SIGNING_STATE_DIR}/signing-identity-sha1}"

mirror_relay_list_signing_identities() {
  security find-identity -p codesigning 2>/dev/null \
    | awk -F '"' '
      /^[[:space:]]*[0-9]+\)/ {
        hash = $1
        sub(/^[[:space:]]*[0-9]+\)[[:space:]]*/, "", hash)
        sub(/[[:space:]]+$/, "", hash)
        if (!(hash in seen)) {
          print toupper(hash) "\t" $2
          seen[hash] = 1
        }
      }
    '
}

mirror_relay_identity_name_for_hash() {
  local expected_hash="${1:u}"
  mirror_relay_list_signing_identities \
    | awk -F '\t' -v expected="${expected_hash}" '$1 == expected { print $2; exit }'
}

mirror_relay_resolve_identity_hash() {
  local requested="$1"
  local matches
  if [[ "${requested}" =~ '^[[:xdigit:]]{40}$' ]]; then
    requested="${requested:u}"
    if [[ -n "$(mirror_relay_identity_name_for_hash "${requested}")" ]]; then
      print -r -- "${requested}"
      return 0
    fi
    print -u2 "Signing identity hash is not available in the keychain: ${requested}"
    return 1
  fi

  matches=$(mirror_relay_list_signing_identities \
    | awk -F '\t' -v expected="${requested}" '$2 == expected { print $1 }')
  if [[ -z "${matches}" ]]; then
    print -u2 "Signing identity is not available in the keychain: ${requested}"
    return 1
  fi
  if [[ "$(print -r -- "${matches}" | wc -l | tr -d ' ')" -ne 1 ]]; then
    print -u2 "More than one signing identity is named '${requested}'."
    print -u2 "Set MIRROR_RELAY_SIGN_IDENTITY to the intended 40-character certificate SHA-1."
    return 1
  fi
  print -r -- "${matches}"
}

mirror_relay_installed_identity_hash() {
  local installed_app="/Applications/Mirror Relay.app"
  [[ -d "${installed_app}" ]] || return 0
  local hash
  hash=$(mirror_relay_signature_leaf_hash "${installed_app}") || return 0
  [[ -n "${hash}" ]] || return 0
  hash="${hash:u}"
  [[ -n "$(mirror_relay_identity_name_for_hash "${hash}")" ]] || return 0
  print -r -- "${hash}"
}

mirror_relay_choose_initial_development_identity() {
  local installed_hash
  installed_hash=$(mirror_relay_installed_identity_hash)
  if [[ -n "${installed_hash}" ]]; then
    print -r -- "${installed_hash}"
    return 0
  fi

  local apple_hashes
  apple_hashes=$(mirror_relay_list_signing_identities \
    | awk -F '\t' '$2 ~ /^Apple Development:/ { print $1 }')
  if [[ -n "${apple_hashes}" ]]; then
    if [[ "$(print -r -- "${apple_hashes}" | wc -l | tr -d ' ')" -ne 1 ]]; then
      print -u2 "Multiple Apple Development identities are available; refusing to choose one implicitly."
      print -u2 "Set MIRROR_RELAY_SIGN_IDENTITY to the intended certificate SHA-1 for the first package:dev run."
      return 1
    fi
    print -r -- "${apple_hashes}"
    return 0
  fi

  local local_hashes
  local_hashes=$(mirror_relay_list_signing_identities \
    | awk -F '\t' -v expected="${MIRROR_RELAY_LOCAL_SIGN_IDENTITY}" \
      '$2 == expected { print $1 }')
  if [[ -n "${local_hashes}" ]]; then
    if [[ "$(print -r -- "${local_hashes}" | wc -l | tr -d ' ')" -ne 1 ]]; then
      print -u2 "Multiple local signing identities are named '${MIRROR_RELAY_LOCAL_SIGN_IDENTITY}'."
      print -u2 "Set MIRROR_RELAY_SIGN_IDENTITY to the intended certificate SHA-1 for the first package:dev run."
      return 1
    fi
    print -r -- "${local_hashes}"
  fi
}

mirror_relay_pinned_development_identity() {
  [[ -f "${MIRROR_RELAY_SIGNING_PIN_FILE}" ]] || return 0
  local pinned_hash
  pinned_hash=$(tr -d '[:space:]' <"${MIRROR_RELAY_SIGNING_PIN_FILE}")
  if [[ ! "${pinned_hash}" =~ '^[[:xdigit:]]{40}$' ]]; then
    print -u2 "Invalid signing pin at ${MIRROR_RELAY_SIGNING_PIN_FILE}."
    print -u2 "Remove it and run npm run signing:doctor to select the signer again."
    return 1
  fi
  pinned_hash="${pinned_hash:u}"
  if [[ -z "$(mirror_relay_identity_name_for_hash "${pinned_hash}")" ]]; then
    print -u2 "Pinned signing identity ${pinned_hash} is no longer available."
    print -u2 "Restore it to the keychain, or deliberately remove ${MIRROR_RELAY_SIGNING_PIN_FILE} to choose another signer."
    return 1
  fi
  print -r -- "${pinned_hash}"
}

mirror_relay_write_signing_pin() {
  local identity_hash="${1:u}"
  mkdir -p "${MIRROR_RELAY_SIGNING_STATE_DIR}"
  local temporary_pin
  temporary_pin=$(mktemp "${MIRROR_RELAY_SIGNING_STATE_DIR}/signing-identity-sha1.XXXXXX")
  print -r -- "${identity_hash}" >"${temporary_pin}"
  mv -f "${temporary_pin}" "${MIRROR_RELAY_SIGNING_PIN_FILE}"
}

mirror_relay_select_development_identity() {
  local requested_identity="${1:-}"
  local pinned_hash
  pinned_hash=$(mirror_relay_pinned_development_identity) || return 1

  if [[ -n "${requested_identity}" ]]; then
    local requested_hash
    requested_hash=$(mirror_relay_resolve_identity_hash "${requested_identity}") \
      || return 1
    if [[ -n "${pinned_hash}" && "${requested_hash:u}" != "${pinned_hash:u}" ]]; then
      print -u2 "Requested signing identity ${requested_hash:u} does not match the pinned identity ${pinned_hash:u}."
      print -u2 "Restore the pinned identity, or deliberately remove ${MIRROR_RELAY_SIGNING_PIN_FILE} before choosing another signer."
      return 1
    fi
    if [[ -z "${pinned_hash}" ]]; then
      mirror_relay_write_signing_pin "${requested_hash}"
    fi
    print -r -- "${requested_hash:u}"
    return 0
  fi

  if [[ -n "${pinned_hash}" ]]; then
    print -r -- "${pinned_hash}"
    return 0
  fi

  local identity_hash
  identity_hash=$(mirror_relay_choose_initial_development_identity) || return 1
  [[ -n "${identity_hash}" ]] || return 0
  mirror_relay_write_signing_pin "${identity_hash}"
  print -r -- "${identity_hash}"
}

mirror_relay_identity_is_available() {
  mirror_relay_resolve_identity_hash "$1" >/dev/null
}

mirror_relay_signature_leaf_hash() {
  local target="${1:A}"
  local temporary_directory
  local hash
  temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/mirror-relay-signing.XXXXXX") \
    || return 1
  if hash=$(
    cd "${temporary_directory}" \
      && codesign -d --extract-certificates "${target}" >/dev/null 2>&1 \
      && shasum -a 1 codesign0 | awk '{ print toupper($1) }'
  ); then
    rm -rf "${temporary_directory}"
    print -r -- "${hash}"
  else
    rm -rf "${temporary_directory}"
    return 1
  fi
}
