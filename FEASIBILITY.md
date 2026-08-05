# Real-iPhone Mirroring Bridge: Feasibility Result

## Decision

Use Apple iPhone Mirroring as the primary locked-device transport, but treat it
as a controlled Mac application rather than an SDK.

Phone Use can wrap the native app with public Mac mechanisms:

1. launch and classify the `com.apple.ScreenContinuity` process;
2. identify its real phone window using WindowServer and Accessibility data;
3. match that window ID in `SCShareableContent`;
4. stream the single window with a desktop-independent ScreenCaptureKit filter;
5. encode selected frames to JPEG in memory for the local agent API;
6. retain exact-window `/usr/sbin/screencapture -l` only as a retrying fallback;
7. post global HID-level CoreGraphics events at captured pixel coordinates only
   when iPhone Mirroring is already frontmost; otherwise fail closed;
8. close the native app to end the route.

ScreenCaptureKit is a public, supported macOS capture framework. Capturing
iPhone Mirroring specifically and global HID delivery are empirically validated
integrations, not a public
iPhone Mirroring automation contract, so macOS updates can still change their
behavior.

## Revised evidence

The original negative ScreenCaptureKit conclusion was wrong. The early probe
did not initialize and catalog WindowServer content in the same way as a normal
AppKit application. A corrected `NSApplication`-backed probe and the production
broker both stream the real Mirroring window successfully.

The remaining limitations are:

- macOS Accessibility exposes Mirroring's Mac window and session controls, not
  the iPhone UI hierarchy;
- ScreenCaptureKit supplies pixels, not iOS semantics;
- process-targeted events do not control the physical phone; reliable synthetic
  input reaches Mirroring through the global HID event stream while the Apple
  app is frontmost;
- the Apple Continuity transport itself has no public third-party SDK.

Phone Use 0.9 uses the public stream for its primary capture path and keeps
the exact-window screenshot path as a fail-safe. The earlier WebDriverAgent
transport remains removed because it requires an unlocked development device
and a separately signed device server.

## Current-machine validation

Proven with the same capture and input code used by the broker:

- selected the real `iPhone Mirroring` window instead of the larger hidden
  welcome window;
- produced six nonblank JPEG frames at 708×1562 showing Apple's live
  **iPhone Not Found** UI;
- posted a normalized process-targeted tap onto **Try Again**;
- captured ten frames with five distinct visual states, with the first change
  occurring immediately after the tap.
- opened a real locked-device session through the exact installed
  `/Applications/Phone Use.app`;
- captured the physical iPhone's live 708×1562 screen through the authenticated
  `/api/observe` endpoint;
- tapped the ChatGPT icon by normalized pixel coordinates and observed the app
  open on the phone;
- executed a phased swipe and observed the ChatGPT list scroll;
- closed through the agent API and verified the native iPhone Mirroring process
  was no longer running.
- streamed the hidden real Mirroring window with public ScreenCaptureKit at
  708×1562: 158 frames in five seconds, 29.43 capture fps, 33.72 ms median and
  36.51 ms p95 delivery interval;
- ran the complete broker pipeline at 12–14 in-memory JPEG fps with fresh frame
  ages normally below 100 ms;
- delivered 43 authenticated MJPEG frames in three seconds through the local
  browser endpoint while the window was behind other apps;
- proved that process-targeted input can report delivery without changing the
  phone, then tested and rejected a global-HID focus-restoration workaround;
- measured the release broker at approximately 12% of one CPU core and 67 MB
  resident memory during continuous capture and JPEG encoding.

## Requirement audit

| Requirement | Result |
| --- | --- |
| Background Mac broker | Implemented as menu-bar app with launch-at-login |
| Local-only agent API | Authenticated listener on `127.0.0.1:8747` |
| Start/close Mirroring | Implemented |
| Observe native window | Public ScreenCaptureKit stream; exact-window fallback |
| Pixel taps and drags | Foreground-only global HID; background attempts fail closed |
| Native-feeling swipe | Implemented with phased continuous scroll events |
| Keyboard and system shortcuts | Implemented |
| Locked iPhone | Proven with the installed app and physical iPhone |
| Powered-off iPhone | Impossible |
| Phone semantic UI tree | Unavailable through Mirroring |
| Zero lifetime consent | Impossible; macOS requires one-time Screen Recording and Accessibility grants |
| Stable permission identity | Requires stable signing; use Developer ID for distribution |

## Important operational limits

- The phone must remain powered on, nearby, and locked.
- Initial Continuity setup and occasional recovery can require a recent manual
  unlock.
- iPhone Mirroring must be available for the Apple Account and region.
- The agent sees pixels, not iOS accessibility nodes. OCR or vision planning
  can be layered on later.
- Observation does not activate or raise iPhone Mirroring. Control never changes
  foreground focus and is unavailable unless Mirroring is already frontmost.
- Apple can break this integration in a macOS update because no iPhone
  Mirroring SDK is documented.

## Deliberate non-goal

USB/XCUITest and WebDriverAgent remain useful for test labs that need semantic
iOS UI data. They are not included in Phone Use because they require
Developer Mode, signing, an unlocked device, and an additional device-side
control server.

## Safety boundary

Phone Use does not patch iPhone Mirroring, inject into Apple processes,
modify the region eligibility database, handle passcodes, or bypass Apple
security. It controls only the user's visible, normally authorized Mac session
and keeps its API loopback-only.

## Apple-private API finding

The installed Apple app links private `ScreenContinuityServices`,
`ScreenSharingKit`, RemoteDisplay, Replicator, UniversalHID, and Wi-Fi
peer-to-peer components. Read-only symbol inspection exposes capabilities such
as a media transport client session, a screen-sharing video layer, video
screenshots, HID reports, system gestures, accessibility messages, and
pairing/session management.

Those symbols confirm that Apple has a lower-level decoded video and input
transport inside its own process. They do not provide an external SDK or a
supported way to attach to the already-running session. The app also carries
Apple-private RemoteDisplay, PairingManager, Replicator, SkyLight, Bluetooth,
and Wi-Fi entitlements that a third-party signed app cannot request.

Depending on those APIs would therefore require unsupported entitlement
forgery, process injection, or recreating Apple’s private pairing and account
state. That route is brittle, unsafe, incompatible with notarized distribution,
and explicitly outside the product. Public ScreenCaptureKit reaches the same
visible pixels without crossing that boundary.
