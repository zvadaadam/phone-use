# Real-iPhone Mirroring Bridge: Feasibility Result

## Decision

Use Apple iPhone Mirroring as the primary locked-device transport, but treat it
as a controlled Mac application rather than an SDK.

Mirror Relay can wrap the native app with public Mac mechanisms:

1. launch and classify the `com.apple.ScreenContinuity` process;
2. locate its largest compositor window;
3. capture the window with `/usr/sbin/screencapture`, using window ID and exact
   region strategies;
4. convert captures to JPEG for the local agent API;
5. activate the app and post global HID-level input at captured pixel
   coordinates;
6. close the native app to end the route.

This is a viable local integration pattern and is independently exercised by
the mature `mirroir-mcp` project. It is not a public Apple contract, so macOS
updates can change its behavior.

## Revised evidence

The original negative conclusion was too broad. These observations remain true:

- a direct ScreenCaptureKit stream produced `SCFrameStatus.suspended`;
- macOS Accessibility exposes Mirroring's Mac window/state, not the iPhone UI
  hierarchy;
- one early `screencapture -l` probe captured uniform phone pixels.

They rule out ScreenCaptureKit streaming and semantic AX automation, but do not
rule out every WindowServer screenshot route. The deeper comparison found a
maintained implementation that uses the `screencapture` service with a
window/region fallback and controls the real app with HID-level events.

Mirror Relay 0.6 implements that narrower route and deliberately ships only the
Apple transport. The earlier WebDriverAgent fallback was removed because it
requires an unlocked development device and exposes a separate unauthenticated
device server, neither of which fits the locked, local-only product boundary.

## Current-machine validation

Proven with the same capture and input code used by the broker:

- selected the real `iPhone Mirroring` window instead of the larger hidden
  welcome window;
- produced six nonblank JPEG frames at 708×1562 showing Apple's live
  **iPhone Not Found** UI;
- injected a normalized HID tap onto **Try Again**;
- captured ten frames with five distinct visual states, with the first change
  occurring immediately after the tap.
- opened a real locked-device session through the exact installed
  `/Applications/Mirror Relay.app`;
- captured the physical iPhone's live 708×1562 screen through the authenticated
  `/api/observe` endpoint;
- tapped the ChatGPT icon by normalized pixel coordinates and observed the app
  open on the phone;
- executed a phased swipe and observed the ChatGPT list scroll;
- closed through the agent API and verified the native iPhone Mirroring process
  was no longer running.

## Requirement audit

| Requirement | Result |
| --- | --- |
| Background Mac broker | Implemented as menu-bar app with launch-at-login |
| Local-only agent API | Authenticated listener on `127.0.0.1:8747` |
| Start/close Mirroring | Implemented |
| Observe native window | Implemented with JPEG window/region capture |
| Pixel taps and drags | Implemented with global HID mouse events |
| Native-feeling swipe | Implemented with phased continuous scroll events |
| Keyboard and system shortcuts | Implemented |
| Locked iPhone | Proven with the installed app and physical iPhone |
| Powered-off iPhone | Impossible |
| Phone semantic UI tree | Unavailable through Mirroring |
| Zero lifetime consent | Impossible; macOS requires one-time Screen Recording and Accessibility grants |
| Stable permission identity | Implemented for local packaging; use Developer ID for distribution |

## Important operational limits

- The phone must remain powered on, nearby, and locked.
- Initial Continuity setup and occasional recovery can require a recent manual
  unlock.
- iPhone Mirroring must be available for the Apple Account and region.
- The agent sees pixels, not iOS accessibility nodes. OCR or vision planning
  can be layered on later.
- Global HID input briefly makes iPhone Mirroring frontmost. This is how the
  native app receives synthetic input.
- Apple can break this integration in a macOS update because no iPhone
  Mirroring SDK is documented.

## Deliberate non-goal

USB/XCUITest and WebDriverAgent remain useful for test labs that need semantic
iOS UI data. They are not included in Mirror Relay because they require
Developer Mode, signing, an unlocked device, and an additional device-side
control server.

## Safety boundary

Mirror Relay does not patch iPhone Mirroring, inject into Apple processes,
modify the region eligibility database, handle passcodes, or bypass Apple
security. It controls only the user's visible, normally authorized Mac session
and keeps its API loopback-only.
