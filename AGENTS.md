# Phone Use agent rules

## Foreground focus is inviolable

- Never activate, raise, focus, or otherwise bring iPhone Mirroring to the
  foreground on the user's behalf.
- Never move focus away from the user's current Mac application, even briefly.
- Do not add an opt-in, fallback, test mode, or command-line flag that bypasses
  this rule.
- Observation may run in the background. Control must fail closed when the
  available backend cannot deliver input without changing Mac focus.
- A control command is not successful merely because an event was posted. It
  must preserve Mac focus and verify the intended phone-side result.
- Real-device tests must record the Mac foreground application before and after
  every control attempt and fail if it changes.

This constraint takes priority over convenience and apparent feature
completeness. A truthful unsupported result is better than hidden focus theft.
