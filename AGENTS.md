# Phone Use agent rules

## Foreground focus is inviolable

- Never use a Mac application window, cursor, keyboard event, or GUI automation
  layer as the phone-control transport.
- Never move focus away from the user's current Mac application, even briefly.
- Detecting or restoring focus after an activation does not satisfy this rule.
- Do not add an opt-in, fallback, test mode, or command-line flag that bypasses
  this rule.
- Observation may run in the background. Control must fail closed unless the
  device transport can deliver input without changing Mac focus.
- A control command is not successful merely because an event was posted. It
  must preserve Mac focus and verify the intended phone-side result.
- Real-device tests must record the Mac foreground application before and after
  every control attempt, sample throughout the attempt, and fail on any
  transient change. A test failure revokes that delivery route before another
  user-facing build is installed.

This constraint takes priority over convenience and apparent feature
completeness. A truthful unsupported result is better than hidden focus theft.
