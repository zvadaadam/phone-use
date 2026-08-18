# Phone Use

Phone Use is a macOS host for AI agents that need to observe and control a real
iPhone. The product direction is direct iOS 27 physical-device access through
Apple Device Hub, exposed as a small authenticated local API and CLI.

> **Architecture checkpoint:** version 0.10 does not control a phone yet. The
> old GUI-based experiment has been removed. The Device Hub transport is a
> typed, fail-closed boundary that reports zero capabilities until a physical
> iOS 27 frame-and-HID test passes.

## What we are building

The intended flow is:

    AI agent → phone-use CLI/API → Apple Device Hub → physical iPhone

Phone Use owns the agent-facing contract, local authentication, action safety,
frame leases, diagnostics, and eventually a separate Internet relay. Apple
Device Hub must own device frames and device input. No Mac application window,
cursor, or keyboard event may be used as a substitute transport.

The target experience is an agent that can connect, observe, tap, swipe, type,
and disconnect without interrupting the person using the Mac.

## Current status

| Surface | Status |
| --- | --- |
| Signed macOS menu app | Built and packaged |
| Authenticated loopback API | Working |
| Swift CLI | Working |
| Typed iOS 27 Device Hub boundary | Built |
| Physical-device frame stream | Not implemented |
| Physical-device HID control | Not implemented |
| Internet relay | Not implemented |

This distinction is intentional. A status response says **unimplemented**,
observation returns HTTP 503, and control returns HTTP 409. There is no fallback
that can steal Mac focus or report an unverified action as successful.

## Requirements

The future physical-device backend targets:

- macOS 15 or newer on Apple silicon;
- an iPhone running iOS 27 or newer;
- Developer Mode on the iPhone;
- USB or an Apple-supported local wireless host connection;
- a compatible Xcode Device Hub runtime.

Device Hub is the local device transport. Connecting over the public Internet
will require a separate authenticated relay and is not part of version 0.10.

## Build from source

This repository currently ships a developer checkpoint, not an end-user
release.

    npm ci
    npm test
    npm run package:app
    open "dist/Phone Use.app"

For a stable local signing identity:

    npm run signing:doctor
    npm run package:dev

The packaged helper is at:

    dist/Phone Use.app/Contents/Helpers/phone-use

## CLI

    phone-use status
    phone-use doctor
    phone-use dashboard
    phone-use connect
    phone-use disconnect
    phone-use observe frame.jpg

Action commands already define the future contract:

    phone-use tap --frame-token TOKEN 0.5 0.5
    phone-use swipe --frame-token TOKEN 0.5 0.8 0.5 0.2 350
    phone-use type --frame-token TOKEN "hello"
    phone-use home --frame-token TOKEN

A frame token is a one-shot capability returned by observation. Actions must
refer to a fresh frame so the backend cannot apply a click to a different or
stale screen.

## Local API

The app listens only on 127.0.0.1:8747. Every route requires either the local
bearer token or a one-time dashboard session.

| Method | Route | Purpose |
| --- | --- | --- |
| GET | /health | Runtime and protocol health |
| GET | /api/status | Device Hub state, proof, requirements, capabilities |
| POST | /api/device/connect | Connect the physical-device transport |
| POST | /api/device/disconnect | Disconnect and clear device state |
| GET | /api/observe | Return one JPEG plus a one-shot frame token |
| POST | /api/actions | Perform a typed action against that frame |

The token lives at ~/Library/Application Support/Phone Use/token with mode
0600. Query-string tokens are rejected. Browser sessions use one-time
bootstraps, HttpOnly cookies, strict origin checks, and DNS-rebinding defense.

## Safety invariants

- Never change the foreground Mac application, even transiently.
- Never route phone control through Mac GUI events.
- Never enable capabilities from environment guesses alone.
- Require physical frame-plus-HID evidence before reporting the backend ready.
- Require a fresh one-shot frame token before every action.
- Keep the API on loopback unless a separately authenticated relay is built.
- Do not persist device frames by default.

## Project map

- native/Sources/PhoneUseProtocol — shared status and command contract
- native/Sources/PhoneUseApp/DeviceHubTransport.swift — sole device boundary
- native/Sources/PhoneUseApp/LocalHTTPServer.swift — authenticated local API
- native/Sources/PhoneUseCLI — CLI client
- public — local diagnostic dashboard
- RESEARCH.md — what was tried, removed, retained, and why
- .autoresearch/locked-iphone-control — raw experimental evidence

See [RESEARCH.md](RESEARCH.md) before adding a transport. A new backend is not
complete until it passes the physical-device and no-focus proof described
there.
