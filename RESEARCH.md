# iPhone Mirroring Automation Repository Review

Review updated: 2026-08-04.

## Recommendation

Use [`leeguooooo/iphone-use`](https://github.com/leeguooooo/iphone-use) as the
primary high-performance capture reference and
[`jfarcand/mirroir-mcp`](https://github.com/jfarcand/mirroir-mcp) as the
pixel-control and agent-tool reference. Keep Mirror Relay's smaller
authenticated loopback API and dashboard.

## `leeguooooo/iphone-use`

Best capture-performance evidence.

- Correctly initializes AppKit before querying WindowServer shareable content.
- Uses a desktop-independent single-window ScreenCaptureKit stream for the
  iPhone Mirroring window.
- Receives BGRA frames at roughly 30 fps, then uses VideoToolbox H.264 and
  WebRTC for browser transport.
- Uses global HID events for control after directly-created targeted CGEvents
  proved insufficient in that implementation.
- Includes a single-controller lease and a broader LAN/WebRTC product surface.

Mirror Relay adopts the public ScreenCaptureKit window stream, but not WebRTC
or LAN access. In-memory JPEG over the existing authenticated loopback MJPEG
route is substantially smaller, preserves the security model, and measured
12–14 end-to-end fps on this Mac. H.264/WebRTC remains a later option if remote
network transport or 30–60 fps human interaction becomes a product goal.

## `jfarcand/mirroir-mcp`

Best agent-tool and control reference.

- Native Swift MCP server with an actively maintained release history.
- Locates and classifies Apple's Mirroring window with AX and WindowServer data.
- Captures through `screencapture -l`, with `screencapture -R` as a fallback.
- Uses global HID-level `CGEvent` input because its directly-created
  `postToPid` events did not register taps in iPhone Mirroring.
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

Mirror Relay adopts its window-classification and phased-scroll lessons, not
its process-per-frame capture path, foreground HID delivery, or full 33-tool
MCP surface. Local testing found a narrower background route: start pointer
events as AppKit `NSEvent` envelopes, add the destination window's WindowServer
metadata, then use `postToPid`. Directly-created CGEvents with only the public
fields still failed, which explains the earlier projects' result. The local
HTTP API is easier for the browser dashboard and for agents that are not MCP
clients.

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

It confirms why WebDriverAgent is not part of the launch product: the route is
more deterministic for a test lab, but adds onboarding and does not provide the
seamless locked-iPhone session Mirror Relay is designed around.

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
6. a separate test-lab product, not a hidden fallback, when semantic iOS UI
   data is required.

It is seamless after consent, but it is not an iPhone Mirroring SDK and cannot
operate a powered-off phone.

## Transport decision

| Route | Real locked phone | Smoothness | Setup | Launchable |
| --- | --- | --- | --- | --- |
| ScreenCaptureKit + process-targeted AppKit events | Yes | 12–30 fps | Apple pairing + two Mac grants | Yes |
| `screencapture -l` + process-targeted AppKit events | Yes | 2–7 fps | Same | Fallback only |
| H.264/WebRTC over SCK | Yes | 30 fps | More dependencies/protocol surface | Later |
| Private ScreenSharingKit | Theoretically | Native | Apple-only entitlements/session state | No |
| USB DVT + WebDriverAgent | Not the locked wireless route | 5–15 fps | Developer Mode, USB/tunnel, signing | Test lab |
| `simctl` / `serve-sim` | Simulator only | Up to 60 fps | Xcode simulator | Different product |
