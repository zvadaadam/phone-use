# Changelog

## Unreleased

- Corrected the earlier conclusion that process-targeted AppKit event envelopes
  control a physical iPhone Mirroring surface. Real-device testing proved that
  reliable control requires global HID input while Mirroring is frontmost.
- Made foreground focus an inviolable boundary. Removed the focus-lease CLI and
  dashboard escape hatch; control now fails closed unless iPhone Mirroring is
  already frontmost, and every action reports whether focus stayed unchanged.
- Removed automatic background presses of Apple's Resume/Connect controls; a
  paused session now waits for the user instead of risking a focus transition.
- Replaced exact JPEG hashes with compact visual fingerprints so stale-frame
  protection tolerates encoding noise and small animations but still rejects a
  meaningful layout change.
- Added honest delivery outcomes for partial gestures, incomplete input,
  unverified visual changes, and failed focus preservation; the CLI and dashboard
  no longer present those outcomes as success.
- Stabilized pointer geometry before delivery, shortened tap and typing timing,
  and kept live capture independent from control attempts.
- Switched real-device typing to physical key events and corrected top-left
  normalized coordinate mapping for global HID delivery.

## 0.9.0 — 2026-08-04

- Reworked the README into a user-facing installation and usage guide with
  one-time setup, CLI reference, troubleshooting, and bounded agent prompts.
- Added a README hero built around a real iPhone lock-screen capture showing
  Apple’s “iPhone in Use” state while the Mac agent controls the device.
- Added URL-safe signed release artifact names and deterministic Homebrew Cask
  generation pinned to the exact DMG checksum.
- Rebranded the repository, macOS app, Swift modules, CLI, dashboard, scripts,
  package metadata, release artifacts, and persisted state namespace to Phone
  Use. Added one-time token and signing-pin migration while retaining the frozen
  bundle identifier and pinned signer so existing macOS privacy grants survive.
- Added permission-stable development packaging that prefers Apple Development,
  supports an exact local self-signed fallback, and fails closed when
  `package:dev` would fall back to an ad-hoc signature.
- Added a signing doctor with exact Xcode certificate setup guidance and made
  ad-hoc package output explicitly warn against replacing a granted install.
- Pinned the exact local development certificate so new or reordered Keychain
  identities cannot silently change the app's macOS privacy identity.
- Replaced the stale iPhone Mirroring child-count heuristic with one fail-closed
  session inspector and a debounced state machine that combines Accessibility
  evidence with fresh capture evidence.
- Replaced foreground HID input with Codex-style AppKit event envelopes posted
  directly to the iPhone Mirroring process, including the private WindowServer
  metadata required for covered and off-current-Space windows.
- Removed Mirroring activation, Space switching, window raising, and Mac cursor
  movement from tap, swipe, typing, and system-shortcut commands.
- Added continuous foreground sampling for live control tests so even a brief
  focus handoff fails the acceptance gate.
- Removed unconditional iPhone Mirroring activation from session health checks;
  Connect and Resume are pressed through background Accessibility actions.
- Kept window-geometry validation exclusive to pointer gestures; keyboard,
  typing, and system shortcuts validate identity without depending on window
  geometry.
- Added bounded stable-window sampling before pointer gestures so resizing or
  rotation cannot redirect a command mid-flight.
- Recognized Apple's accessibility-opaque live phone surface as connected while
  continuing to treat visible status, error, and action overlays as paused.
- Made frame publication atomic with session truth: pre-connection frames are
  dropped, every disconnect clears published frame/FPS state, and reconnect
  requires a newly captured frame before observation reopens.

## 0.8.0 — 2026-08-01

- Moved the Swift CLI from `Contents/Resources` to Apple’s supported
  `Contents/Helpers` bundle location and removed its capture-framework link.
- Split wire commands and compatibility metadata into a lightweight Swift
  protocol module with bundle-discovery tests.
- Added product and protocol handshakes so the CLI rejects stale running app
  copies instead of silently controlling an incompatible broker.
- Required authentication on every route and added literal loopback `Host`
  validation alongside the existing session-cookie and `Origin` protections.
- Added bundle verification for layout, versions, architectures, hardened
  runtime, nested signatures, framework links, Developer ID teams, Gatekeeper,
  and notarization tickets.
- Replaced the ZIP release with an app-and-DMG notarization pipeline that emits
  a stapled disk image and SHA-256 checksum.
- Froze the pre-release bundle identifier as `com.adamzvada.mirrorrelay`.

## 0.7.0 — 2026-07-30

- Replaced process-per-frame primary capture with an in-memory, single-window
  ScreenCaptureKit stream.
- Added full-resolution 15 fps JPEG gating and retained the hardened
  exact-window screenshot implementation as an automatic retrying fallback.
- Added exact-window heartbeat frames for idle streams and automatic stream
  reconfiguration when the Mirroring window rotates, resizes, or changes scale.
- Hardened startup against an immediate ScreenCaptureKit delegate failure and
  accepted only complete ScreenCaptureKit frames.
- Added structured capture-mode status, centralized and unit-tested capture
  policy decisions, and an opt-in real-device FPS/resolution/MJPEG smoke gate.
- Made hidden/off-current-space Mirroring windows eligible for the stream
  without broadening capture beyond the selected window.
- Added stream sizing and rate-gate tests.
- Corrected the feasibility record and documented the rejected Apple-private
  transport route.

## 0.6.0 — 2026-07-30

- Consolidated the product around Apple iPhone Mirroring and removed the legacy
  unauthenticated Node relay and WebDriverAgent fallback.
- Replaced phased browser pointer traffic with atomic tap and swipe commands.
- Serialized session and control mutations.
- Added per-event target, focus, bounds, and topmost-window verification.
- Made capture window-only and isolated transient source PNGs in private,
  per-process scratch directories.
- Added fresh-frame expiry and frame clearing on disconnect or close.
- Replaced browser bearer-token URLs with one-time bootstrap links and
  HttpOnly, SameSite-strict sessions.
- Added `dashboard`, `doctor`, and `version` CLI commands.
- Added isolated auth/integration coverage and Developer ID notarization
  packaging.

## 0.5.0 — 2026-07-30

- Proved live capture and pixel control of a locked physical iPhone through
  Apple iPhone Mirroring.
- Added the native menu-bar broker, loopback API, dashboard, and CLI.
