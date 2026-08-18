# Changelog

## 0.10.0

- Replaced the experimental runtime with one iOS 27 Device Hub transport
  boundary.
- Deleted the old capture, session, Mac input, and fallback implementation
  graph, including its dedicated core target and tests.
- Added explicit runtime requirements, proof state, focus policy, frame status,
  and capability reporting.
- Renamed device lifecycle routes and CLI commands to connect and disconnect.
- Made observation and control fail closed until physical frame-plus-HID
  validation exists.
- Removed obsolete macOS privacy prompts and adopted the
  com.adamzvada.phoneuse bundle identifier.
- Simplified the dashboard to present the actual implementation state.
- Preserved loopback authentication, one-time dashboard sessions, signing,
  packaging verification, and typed command validation.
- Consolidated architectural history and experimental evidence in RESEARCH.md.
