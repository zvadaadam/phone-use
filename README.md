# Mirror Relay

Mirror Relay is a local macOS broker that lets authorized agents observe and
control a real, powered-on iPhone through Apple’s iPhone Mirroring app.

```text
agent CLI / authenticated dashboard
        ↕ HTTP on 127.0.0.1:8747
Mirror Relay menu-bar app
        ↕ ScreenCaptureKit + verified process-targeted input
Apple iPhone Mirroring
        ↕ Apple Continuity
nearby, powered-on, locked iPhone
```

The browser does not embed Apple’s private UI and Mirror Relay does not patch or
inject into Apple processes. It streams only the authorized iPhone Mirroring
window through Apple’s public ScreenCaptureKit API, encodes frames in memory,
maps normalized coordinates to that window, verifies the target before every
input event, and posts AppKit/CoreGraphics events directly to the Mirroring
process.

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
- an Apple Development or local self-signed Code Signing identity for
  permission-persistent source builds;
- Node.js 20 or newer for tests and packaging.

Prefer Apple Development from **Xcode → Settings → Accounts → Manage
Certificates**. If a Personal Team certificate is unavailable, create a
local-only identity in **Keychain Access → Certificate Assistant → Create a
Certificate** with the name `Mirror Relay Local Development`, identity type
**Self-Signed Root**, and certificate type **Code Signing**. Verify the selected
channel and build the permission-stable app:

```sh
npm install
npm run signing:doctor
npm run package:dev
```

Copy `dist/Mirror Relay.app` to `/Applications`, open it, and grant the exact
installed app:

- **Privacy & Security → Screen & System Audio Recording**
- **Privacy & Security → Accessibility**

Relaunch Mirror Relay after changing either permission. The signing doctor pins
the exact certificate SHA-1 in the ignored `.mirror-relay` state directory, and
future development builds fail instead of silently switching certificates.
Keep the bundle ID and that pinned certificate unchanged. Apple Development and
the local self-signed identity both preserve one local designated requirement;
Developer ID-signed releases do the same for customers. The self-signed channel
is local development only and is not suitable for distribution.

`npm run package:app` remains available for CI and isolated package checks when
no certificate is installed, but its ad-hoc output must not replace a granted
development install: every changed ad-hoc binary has a new CDHash and therefore
a new macOS privacy identity.

Public releases are distributed as a notarized `Mirror Relay-<version>.dmg`.
Drag the app to the Applications shortcut in the disk image. The app, its Swift
CLI helper, and the disk image are signed; Bun, Node, Electron, and JavaScript
runtimes are not shipped.

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

The packaged Swift helper lives at:

```text
/Applications/Mirror Relay.app/Contents/Helpers/mirror-relay
```

It discovers its enclosing app before consulting Launch Services, launches the
broker when needed, and rejects stale brokers with a different product or wire
protocol version. The helper does not link ScreenCaptureKit and does not need a
separate Screen Recording grant.

Coordinates are normalized from `0` to `1`. Tap and swipe are atomic commands;
the broker serializes all open, control, and close operations. Action responses
include frame IDs and whether a fresh frame changed after the command.

### Mac focus behavior

Mirror Relay never activates or raises iPhone Mirroring, switches Spaces, or
moves the Mac pointer. Pointer events begin as an AppKit `NSEvent`, receive the
target Mirroring window's WindowServer metadata, and are posted directly to the
Mirroring process. Keyboard and scroll events use the same process-targeted
route. This is the event envelope used by Codex computer use and remains
addressable while Mirroring is covered or on another Space.

`npm start` opens the authenticated dashboard through the installed CLI.

## Local API

Mirror Relay listens only on `127.0.0.1:8747`. Its 256-bit agent bearer token is
stored in a `0700` directory with `0600` file permissions:

```text
~/Library/Application Support/Mirror Relay/token
```

Every route, including `/health` and static dashboard assets, requires the
bearer token or an authenticated dashboard session. The one-time dashboard
bootstrap URL is itself an expiring credential.

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
- Browser requests with an `Origin` header reject cross-origin access.
- Every HTTP request must use the literal `127.0.0.1:<port>` host, preventing a
  DNS-rebinding origin from reaching the broker.
- Commands are bounded and validated, and mutations run in FIFO order.
- Pointer gestures are sent as one tap or swipe instead of interleaved phases.
- Input revalidates the target PID, window ID, and stable bounds before every
  event and throughout a swipe. It never activates another Mac application.
- Capture is window-only and fails closed; it never falls back to a screen
  region that could contain unrelated Mac windows.
- The primary capture path is an in-memory ScreenCaptureKit stream capped at 15
  JPEG frames per second. If that stream cannot start, the broker retries it
  while using an exact-window `screencapture -l` fallback. The same hardened
  fallback supplies heartbeat frames when ScreenCaptureKit intentionally idles
  on an unchanged screen.
- One debounced session state machine combines Accessibility evidence with a
  fresh capture signal. Frames are dropped until that state is stable; closing
  or losing the session atomically clears the cached frame and FPS, and a new
  post-reconnect frame is required before observation reopens.
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
npm run test:focus       # opt-in live command with continuous no-focus sampling
npm run verify:package   # bundle layout, versions, links, and signatures
npm run check            # tests, warnings-as-errors release build, package
```

The integration test verifies loopback binding, bearer authentication,
single-use dashboard exchange, hardened cookies, host/origin rejection,
protocol metadata, validation, and token permissions. Native tests cover
command validation, operation
serialization, fallback capture commands, stream frame-rate gating and sizing,
Mirroring-window selection, debounced session-state evidence, atomic frame
publication, stable geometry, and process-targeted event metadata.

## Release packaging

`npm run package:dev` pins and uses one exact certificate SHA-1. For a first
build it preserves the installed app's available signer, otherwise accepts one
unambiguous Apple Development identity or the exact `Mirror Relay Local
Development` local fallback. It fails if the pinned signer disappears or a
choice would be ambiguous. `npm run package:app` uses that same pin, otherwise
it produces an ad-hoc artifact and prints a permission-persistence warning.

A distributable build must use Apple Developer credentials:

```sh
export MIRROR_RELAY_SIGN_IDENTITY="Developer ID Application: …"
export MIRROR_RELAY_NOTARY_PROFILE="mirror-relay-notary"
npm run package:release
```

The release command signs nested executables, submits the archive to Apple
notary service, staples and validates the app and disk-image tickets, checks
Gatekeeper acceptance, and creates `dist/Mirror Relay-<version>.dmg` plus a
SHA-256 file. It fails closed when either credential is missing. See
[PACKAGING.md](PACKAGING.md) for the identity policy and release checklist.

## Source layout

- `native/Sources/MirrorCore` — capture, verified input, policies, and FIFO lock.
- `native/Sources/MirrorRelayProtocol` — runtime-independent wire commands,
  bundle discovery, and compatibility version.
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
