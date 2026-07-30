# iPhone Mirroring Automation Repository Review

Review date: 2026-07-30.

## Recommendation

Use [`jfarcand/mirroir-mcp`](https://github.com/jfarcand/mirroir-mcp) as the
technical reference, but keep Mirror Relay's own loopback API and dashboard.
It is the only reviewed project centered on Apple's locked, wireless iPhone
Mirroring session rather than a simulator or USB device automation.

## `jfarcand/mirroir-mcp`

Best fit.

- Native Swift MCP server with an actively maintained release history.
- Locates and classifies Apple's Mirroring window with AX and WindowServer data.
- Captures through `screencapture -l`, with `screencapture -R` as a fallback.
- Uses global HID-level `CGEvent` input because `postToPid` does not register
  taps in iPhone Mirroring.
- Implements trackpad-like phased scrolling for iOS swipes.
- Adds Apple Vision OCR and optional model-based perception.
- Exposes a broad MCP tool surface with fail-closed, read-only permissions by
  default and no network listener.
- Documents direct Codex MCP installation.

Local verification:

- the official 0.35.1 arm64 release checksum verified and its MCP handshake,
  status, doctor, and permission model ran successfully;
- `doctor --json` confirmed this Mac's iPhone Mirroring process plus Screen
  Recording and Accessibility permissions;
- live screenshot could not be proven during the review because the native app
  reported the iPhone session as paused/not found;
- a source release build failed at link time when its optional `embacle` FFI
  library was absent, so the release binary was more reliable than a clean
  source build on this machine.

Mirror Relay adopts the transport pattern, not the full 33-tool MCP surface.
Its existing HTTP API is easier for a browser dashboard and for agents that are
not MCP clients.

## `Pauli1Go/iphone-mirroring-eu-enabler`

Not an automation transport.

The project changes
`/private/var/db/os_eligibility/eligibility.plist`, specifically the Iron
eligibility domain, under elevated privileges and then opens iPhone Mirroring.
It provides no screenshot stream, input API, lifecycle broker, or agent
interface.

Risks:

- mutates a protected system eligibility database;
- requires Full Disk Access and administrator privileges;
- can be invalidated by macOS updates;
- broad eligibility edits are unrelated to agent control.

Mirror Relay does not run or embed it. If the native app already opens and
connects, there is no reason to touch the eligibility database.

## `Dennisjoch/iPhoneMirroring`

Useful USB fallback reference, not a match for the locked wireless goal.

It combines:

- `pymobiledevice3` DVT screenshot capture over USB/tunnel;
- WebDriverAgent for control;
- Developer Mode, pairing, tunneld/root setup, and Xcode signing.

That is the same class of trade-off as Mirror Relay's WebDriverAgent fallback:
more deterministic device automation, but more onboarding and no seamless
locked iPhone Mirroring session.

## Other relevant projects

### Peekaboo

A strong generic macOS capture and UI-automation toolkit. It is useful for
window discovery and ScreenCaptureKit patterns, but it is not specifically a
locked-iPhone transport and does not solve Mirroring's HID and protected-surface
quirks by itself.

### Understudy

Demonstrates generic screenshot/GUI agent flows and mentions iPhone Mirroring.
Its test harness does not establish a real locked-iPhone session, so it is
weaker evidence than `mirroir-mcp`.

### `serve-sim`

Good inspiration for the browser experience and agent-facing control loop, but
simulators expose supported developer APIs. A physical iPhone through
Continuity requires the native Mac-window capture/input adapter described
above.

## Product conclusion

The best agent experience is:

1. one-time Apple iPhone Mirroring setup;
2. one-time Screen Recording and Accessibility grants for a stably signed Mac
   broker;
3. background launch at login;
4. authenticated local `open → observe/act → close` calls;
5. pixel/OCR/vision planning above the broker;
6. explicit WDA fallback only when semantic iOS UI data is required.

It is seamless after consent, but it is not an iPhone Mirroring SDK and cannot
operate a powered-off phone.
