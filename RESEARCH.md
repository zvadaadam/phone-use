# Architecture history and evidence

This is the one historical document for approaches removed from Phone Use.
Raw probes and results remain under .autoresearch/locked-iphone-control so the
same dead ends do not need to be rediscovered.

## Product requirement

An agent should observe and control a locked physical iPhone from a Mac without
changing the Mac foreground application. The eventual system should also work
across the Internet, but remote transport is a separate layer from the local
Mac-to-iPhone link.

## What we tried

### Apple iPhone Mirroring as a GUI transport

The first implementation attached to Apple iPhone Mirroring, selected its
window, captured that window with ScreenCaptureKit, and exposed JPEG frames over
the local API. This proved that a hidden or background Mirroring window could
sometimes be observed.

Control was the blocker. Public macOS event delivery was insufficient, and
process/window-targeted SkyLight experiments could report event delivery while
still activating iPhone Mirroring. Because any transient focus change violates
the product requirement, the route remained disabled.

macOS Screen Recording and Accessibility consent also belonged to the signed
host app, not the web page or CLI. Rebuild identity and permission persistence
made the approach operationally brittle.

### WebDriverAgent and XCUITest

This route offered semantic automation for development devices, but required a
signed runner, an active test session, developer provisioning, and behavior that
did not match the desired locked everyday-phone experience. It was removed as a
product fallback.

### pymobiledevice3 and CoreDevice probes

pymobiledevice3 was useful as research into pairing, Remote Service Discovery,
developer services, and device tunnels. It did not by itself provide the
complete locked-device screen-plus-HID product contract. Its GPL code is not
copied into Phone Use.

Direct CoreDevice probes discovered Apple-private services and confirmed that
tooling availability, device OS support, and authenticated service setup are
separate gates. Several service endpoints accepted connections but did not
produce a validated frame-plus-control loop on the available phone.

### Device Hub experiments

The most promising architecture is Apple Device Hub on iOS 27: device-level
frames and HID without using a Mac application window. The available test phone
did not run the required OS, so the experiment could not complete the decisive
physical test. No production implementation is claimed.

## What version 0.10 removed

- the Mirroring process and window detector;
- ScreenCaptureKit and screenshot capture;
- Accessibility session inspection;
- Mac pointer and keyboard event synthesis;
- private SkyLight event routing;
- focus monitors that tried to detect damage after GUI input;
- WebDriverAgent/XCUITest fallback code;
- old session, capture, permission, and delivery fields;
- device and focus scripts tied to the discarded runtime;
- tests that only proved behavior of those deleted abstractions.

The entire PhoneUseCore target disappeared because it existed to support that
graph. This was a deletion, not a compatibility wrapper.

## What remains

- a signed Swift menu app;
- a restricted token and one-time browser-session exchange;
- an authenticated 127.0.0.1 HTTP API;
- a Swift CLI that launches the app without activation;
- typed commands with normalized coordinates and one-shot frame tokens;
- explicit requirements, proof state, and capabilities;
- packaging and signature verification;
- the never-change-Mac-focus invariant;
- raw experimental evidence in .autoresearch.

The app bundle identifier changed to com.adamzvada.phoneuse because the new
runtime no longer needs old privacy grants.

## Current decision

Phone Use has one production architecture: iOS 27 Device Hub. The current
transport implementation is intentionally a fail-closed placeholder. It may
become ready only after all of these pass on a physical device:

1. receive fresh device frames while the iPhone is in the required state;
2. send tap, swipe, keyboard, and system actions through device HID;
3. verify each action with a later device frame;
4. record the foreground Mac application throughout and observe no change;
5. reconnect after app, Mac, and iPhone restarts;
6. characterize USB and Apple-supported local wireless behavior;
7. publish the exact supported Xcode, macOS, and iOS matrix.

Internet access comes later as an authenticated relay to a trusted Mac host.
It must not be confused with Device Hub’s local connection or implemented by
exposing the loopback API directly.
