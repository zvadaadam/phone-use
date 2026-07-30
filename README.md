# Mirror Relay

Mirror Relay is a local Mac broker that lets authorized local AI agents observe
and control a real iPhone through Apple's iPhone Mirroring app.

Version 0.5 makes iPhone Mirroring the default transport:

```text
local agent / browser dashboard
        ↕ authenticated HTTP on 127.0.0.1:8747
Mirror Relay menu-bar + login-item app
        ↕ JPEG window capture + HID-level macOS input
Apple iPhone Mirroring
        ↕ Apple's private Continuity connection
powered-on, nearby, locked iPhone
```

The browser does not embed Apple's native window. Mirror Relay captures that
window, converts it to a JPEG stream, and maps normalized browser/API
coordinates back to global Mac coordinates. It activates iPhone Mirroring and
posts the same HID-level mouse, scroll, and keyboard events that physical input
uses.

## What this can and cannot do

It can:

- launch iPhone Mirroring on demand;
- observe its current window through `/api/observe` or `/stream.mjpeg`;
- tap pixels, drag, perform trackpad-style swipes, and send text;
- invoke Home, App Switcher, and Spotlight;
- close the Mirroring session when the agent is finished;
- start automatically at Mac login and remain local to this Mac.

It cannot:

- operate a powered-off iPhone;
- bypass the iPhone passcode, Apple Account, region, or Continuity checks;
- expose the phone's semantic accessibility tree through Apple Mirroring;
- guarantee compatibility with future macOS releases, because iPhone Mirroring
  has no public automation SDK.

The iPhone must be powered on, nearby, and locked. Apple's first connection may
require the phone to have been recently unlocked. Wi-Fi and Bluetooth must be
enabled and Apple's normal iPhone Mirroring prerequisites still apply.

## Why the capture implementation changed

The first implementation used a `SCStream` directly against the Mirroring
window. On this Mac that path returned suspended samples, and an early
`screencapture` probe appeared blank. A deeper audit of
[`jfarcand/mirroir-mcp`](https://github.com/jfarcand/mirroir-mcp) showed the
working distinction:

- use Accessibility and the WindowServer only to locate and classify the
  Mirroring window;
- acquire each frame through the macOS `screencapture` service, trying window
  ID first and an exact screen-region fallback second;
- post pointing events at the global HID tap, not directly to the app PID;
- model an iPhone swipe as a phased, continuous scroll gesture rather than a
  mouse drag.

Mirror Relay 0.5 now follows that architecture behind its existing API.
WebDriverAgent remains an explicit fallback for cases that need a semantic
accessibility tree. The repository comparison is in
[RESEARCH.md](RESEARCH.md), and the evidence/limitations are in
[FEASIBILITY.md](FEASIBILITY.md).

On the development Mac, the exact installed app completed the full physical
device loop: open the locked iPhone, capture live 708×1562 frames, tap the
ChatGPT icon by normalized coordinates, observe the app open, perform a phased
swipe, and close iPhone Mirroring cleanly.

## One-time setup

1. Set up Apple's iPhone Mirroring normally and confirm it can connect to the
   locked iPhone.
2. Install and open `Mirror Relay.app`.
3. Grant the exact installed app:
   - **Privacy & Security → Screen & System Audio Recording**
   - **Privacy & Security → Accessibility**
4. Relaunch Mirror Relay after changing either permission.

The app requests missing permissions on first launch. Ad-hoc local builds need
the grants refreshed when their code hash changes. Use a stable Apple
Development or Developer ID identity to preserve permissions across rebuilds
and for distribution.

The EU eligibility enabler is not part of Mirror Relay. If iPhone Mirroring
already opens and connects, do not modify the system eligibility database.

## Build, package, and test

Requirements:

- macOS 15 or newer;
- Xcode and its command-line tools;
- Node.js 20 or newer for the dashboard tests and legacy development relay.

```sh
npm test
npm run test:wda-contract
npm run package:app
```

The packaged app is `dist/Mirror Relay.app`.

Tests cover eight Node contracts, eighteen native command/capture/WDA contracts,
and a full isolated broker/WebDriverAgent fallback lifecycle.

## Agent CLI

Agents should use the wrapper instead of reading or handling the bearer token:

```sh
./scripts/mirror-relayctl status
./scripts/mirror-relayctl open
./scripts/mirror-relayctl observe /tmp/iphone.jpg
./scripts/mirror-relayctl tap 0.50 0.72
./scripts/mirror-relayctl swipe 0.50 0.80 0.50 0.25 350
./scripts/mirror-relayctl type "hello"
./scripts/mirror-relayctl home
./scripts/mirror-relayctl apps
./scripts/mirror-relayctl spotlight
./scripts/mirror-relayctl close
```

Coordinates are normalized from `0` to `1` over the captured Mirroring window.
An action response reports the frame IDs before and after the command and
whether the observed image changed.

The wrapper prefers `/Applications/Mirror Relay.app`, then the locally packaged
app. The npm equivalent is:

```sh
npm run relay -- status
```

## Local API

Mirror Relay listens only on `127.0.0.1:8747`. Its random 256-bit token is
stored with mode `0600` under:

```text
~/Library/Application Support/Mirror Relay/token
```

`/health` is the only unauthenticated endpoint.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Liveness, selected transport, and permission summary |
| `GET` | `/api/status` | Phase, frame rate, dimensions, and recent logs |
| `GET` | `/api/observe` | Latest JPEG plus `X-Frame-ID` |
| `GET` | `/api/source` | JSON accessibility tree on the WDA fallback; `409` on Mirroring |
| `GET` | `/stream.mjpeg` | Live multipart JPEG stream |
| `POST` | `/api/session/open` | Launch/connect and wait for a live locked-iPhone session |
| `POST` | `/api/session/close` | Close iPhone Mirroring or the fallback session |
| `POST` | `/api/act` | Validate and deliver a control command |

Example actions:

```json
{"type":"tap","x":0.5,"y":0.72}
{"type":"swipe","x":0.5,"y":0.8,"x2":0.5,"y2":0.2,"durationMs":350}
{"type":"type","text":"hello"}
{"type":"shortcut","name":"home"}
```

Open the dashboard from the app's menu so its one-time URL token is supplied
and then removed from the visible address bar.

## WebDriverAgent fallback

Select the USB/XCUITest transport explicitly:

```sh
MIRROR_RELAY_TRANSPORT="webdriveragent" \
  open "dist/Mirror Relay.app"
```

It requires the normal real-device preparation: USB pairing, Developer Mode,
Xcode signing, and an unlocked phone during automation. It supplies screenshots,
deterministic input, and the semantic `/api/source` tree. Test it without a
physical device using:

```sh
npm run test:wda-contract
```

## Security model

- The broker binds only to IPv4 loopback.
- Observation and control endpoints require the random local bearer token.
- Frames, typed text, and interaction history are not persisted.
- Commands are size- and range-validated.
- Closing iPhone Mirroring ends the native input route.
- There is no LAN listener, cloud relay, passcode handling, jailbreak, or
  private-entitlement injection.

Anyone who controls this macOS account and can read the token can operate the
Mirroring session. Do not expose port 8747 through a proxy or tunnel.

## Source layout

- `native/Sources/MirrorCore` — window capture, input, command model, and WDA client.
- `native/Sources/MirrorRelayApp` — menu-bar app, transports, state, token, and API.
- `native/Sources/MirrorRelayCLI` — agent-facing client and background app launch.
- `public` — bundled local dashboard.
- `scripts/wda-contract-smoke.sh` — isolated fallback lifecycle test.
- `src` — legacy Node development relay.
