# Changelog

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
