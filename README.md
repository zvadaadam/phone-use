# Mirror Relay

Mirror Relay is a local macOS broker that lets authorized agents observe and
control a real, powered-on iPhone through Apple’s iPhone Mirroring app.

```text
agent CLI / authenticated dashboard
        ↕ HTTP on 127.0.0.1:8747
Mirror Relay menu-bar app
        ↕ ScreenCaptureKit + verified HID input
Apple iPhone Mirroring
        ↕ Apple Continuity
nearby, powered-on, locked iPhone
```

The browser does not embed Apple’s private UI and Mirror Relay does not patch or
inject into Apple processes. It streams only the authorized iPhone Mirroring
window through Apple’s public ScreenCaptureKit API, encodes frames in memory,
maps normalized coordinates to that window, verifies the target before every
input event, and posts ordinary macOS HID events.

## Product boundary

Mirror Relay can:

- open and close Apple iPhone Mirroring on demand;
- stream the visible iPhone screen to a local authenticated dashboard;
- return an individual JPEG frame to an agent;
- tap, swipe, type, and invoke Home, App Switcher, or Spotlight;
- start at Mac login and remain available as a menu-bar app.

It cannot:

- operate a powered-off or distant iPhone;
- bypass a passcode, Apple Account, region, or Continuity requirement;
- expose a semantic iOS accessibility tree;
- guarantee compatibility with future macOS releases because Apple publishes no
  iPhone Mirroring automation SDK.

The iPhone must be powered on, nearby, and locked. Apple’s first connection or
recovery flow may require the phone to have been unlocked recently. Wi-Fi,
Bluetooth, and Apple’s normal iPhone Mirroring prerequisites still apply.

## Install and one-time setup

Requirements:

- macOS 15 or newer;
- Apple iPhone Mirroring already paired with the iPhone;
- Xcode command-line tools for source builds;
- Node.js 20 or newer for tests and packaging.

Build the local app:

```sh
npm install
npm run check
```

Copy `dist/Mirror Relay.app` to `/Applications`, open it, and grant the exact
installed app:

- **Privacy & Security → Screen & System Audio Recording**
- **Privacy & Security → Accessibility**

Relaunch Mirror Relay after changing either permission. Ad-hoc local builds can
need their grants refreshed when the binary changes. A Developer ID-signed
release preserves a stable signing identity.

The EU eligibility enabler is not part of Mirror Relay. If Apple’s app already
connects, do not modify the macOS eligibility database.

## Agent CLI

Use the wrapper so agents never read or handle the bearer token directly:

```sh
./scripts/mirror-relayctl dashboard
./scripts/mirror-relayctl doctor
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
./scripts/mirror-relayctl version
```

Coordinates are normalized from `0` to `1`. Tap and swipe are atomic commands;
the broker serializes all open, control, and close operations. Action responses
include frame IDs and whether a fresh frame changed after the command.

`npm start` opens the authenticated dashboard through the installed CLI.

## Local API

Mirror Relay listens only on `127.0.0.1:8747`. Its 256-bit agent bearer token is
stored in a `0700` directory with `0600` file permissions:

```text
~/Library/Application Support/Mirror Relay/token
```

`/health` and static dashboard assets are public to the local Mac. Phone data
and mutation routes require authentication.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Broker liveness and permission summary |
| `GET` | `/api/status` | Phase, capture mode, frame age, dimensions, and recent logs |
| `GET` | `/api/observe` | Fresh JPEG plus `X-Frame-ID` |
| `GET` | `/stream.mjpeg` | Live multipart JPEG stream |
| `POST` | `/api/session/open` | Open and wait for a live session |
| `POST` | `/api/session/close` | Close Mirroring and clear the cached frame |
| `POST` | `/api/act` | Deliver a validated atomic control command |
| `POST` | `/api/dashboard/bootstrap` | Create a one-time dashboard link |

The CLI authenticates with the bearer token. The browser never receives that
long-lived token: a single-use, 60-second bootstrap link is exchanged for an
eight-hour, in-memory, HttpOnly, SameSite-strict session cookie. Bootstrap links
cannot be replayed and dashboard sessions disappear when Mirror Relay quits.

## Security and privacy model

- The broker binds only to IPv4 loopback and uses Network.framework’s
  local-only mode.
- Observation and control endpoints require a bearer token or dashboard
  session.
- Browser mutations reject cross-origin requests.
- Commands are bounded and validated, and mutations run in FIFO order.
- Pointer gestures are sent as one tap or swipe instead of interleaved phases.
- Input revalidates the target PID, window ID, bounds, frontmost application,
  and topmost window before every event and throughout a swipe.
- Capture is window-only and fails closed; it never falls back to a screen
  region that could contain unrelated Mac windows.
- The primary capture path is an in-memory ScreenCaptureKit stream capped at 15
  JPEG frames per second. If that stream cannot start, the broker retries it
  while using an exact-window `screencapture -l` fallback. The same hardened
  fallback supplies heartbeat frames when ScreenCaptureKit intentionally idles
  on an unchanged screen.
- Closing or losing the session clears the cached frame, and observations older
  than three seconds are rejected.
- No LAN listener, cloud relay, passcode handling, jailbreak, private
  entitlement injection, or WebDriverAgent server is included.

The normal ScreenCaptureKit path keeps source frames and JPEG encoding in
memory. Apple’s fallback `screencapture` service requires a file destination;
only when that fallback is active does a source PNG briefly exist inside a
per-user `0700` scratch directory. It is set to `0600`, converted to JPEG in
memory, and deleted immediately. Stale scratch files are scrubbed at startup.
Mirror Relay does not retain frames, typed text, or interaction history. An
explicit CLI `observe` command writes the requested JPEG to the caller’s chosen
path.

Anyone controlling this macOS account and able to invoke the CLI can operate the
paired phone. Do not proxy or tunnel port 8747.

## Tests

```sh
npm test                 # Node, Swift, and isolated broker integration
npm run test:smoke       # exact installed app
npm run test:device      # opt-in live paired-iPhone stream/fps check
npm run check            # tests, warnings-as-errors release build, package
```

The integration test verifies loopback binding, bearer authentication,
single-use dashboard exchange, hardened cookies, origin rejection, validation,
and token permissions. Native tests cover command validation, operation
serialization, fallback capture commands, stream frame-rate gating and sizing,
and Mirroring-window selection.

## Release packaging

`npm run package:app` produces an ad-hoc signed local-development app.

A distributable build must use Apple Developer credentials:

```sh
export MIRROR_RELAY_SIGN_IDENTITY="Developer ID Application: …"
export MIRROR_RELAY_NOTARY_PROFILE="mirror-relay-notary"
npm run package:release
```

The release command signs nested executables, submits the archive to Apple
notary service, staples and validates the ticket, checks Gatekeeper acceptance,
and creates `dist/Mirror Relay-<version>.zip`. It fails closed when either
credential is missing.

## Source layout

- `native/Sources/MirrorCore` — capture, verified input, commands, and FIFO lock.
- `native/Sources/MirrorRelayApp` — menu-bar lifecycle, broker state, auth, and
  local HTTP server.
- `native/Sources/MirrorRelayCLI` — token-hiding agent CLI.
- `native/Tests` — native behavior and concurrency tests.
- `public` — authenticated local dashboard.
- `scripts` — packaging, release, integration, and installed-app smoke checks.
- `test` — browser geometry tests.

The repository comparison and platform evidence are documented in
[RESEARCH.md](RESEARCH.md) and [FEASIBILITY.md](FEASIBILITY.md). Release history,
privacy details, and the security boundary live in [CHANGELOG.md](CHANGELOG.md),
[PRIVACY.md](PRIVACY.md), and [SECURITY.md](SECURITY.md).
