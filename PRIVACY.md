# Privacy

Mirror Relay processes the visible contents of Apple’s iPhone Mirroring window
locally on the Mac.

- Frames are served only through the authenticated loopback API.
- The broker retains only the latest fresh JPEG in memory and clears it when the
  session closes or capture is unavailable.
- The normal ScreenCaptureKit path captures and encodes frames entirely in
  memory. If that stream is unavailable or idle, Apple’s exact-window
  screenshot service briefly writes a source PNG inside a private per-process
  `0700` scratch directory. The file is set to `0600`, deleted after conversion,
  and stale directories are removed when their owner process no longer exists.
- Typed text and interaction history are not persisted.
- The CLI writes a frame only when the caller explicitly uses `observe` and
  chooses an output path.
- No analytics, telemetry, cloud service, or third-party device-control server
  is included.

Mirror Relay requires Screen Recording and Accessibility because those are the
macOS permissions needed to capture and control Apple’s Mirroring window. Those
permissions can be revoked at any time in System Settings.
