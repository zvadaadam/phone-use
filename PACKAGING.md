# Mirror Relay Packaging

Mirror Relay ships as one native, menu-bar macOS app. The main Swift executable
owns Screen Recording and Accessibility consent. Its embedded Swift CLI is a
loopback protocol client and must never perform capture or input itself.

```text
Mirror Relay.app/
└── Contents/
    ├── MacOS/Mirror Relay
    ├── Helpers/mirror-relay
    ├── Resources/public/
    └── Info.plist
```

Apple’s supported `Contents/Helpers` location keeps executable code out of the
resource seal. The verifier also ensures that only the main executable links
ScreenCaptureKit.

## Identity policy

The bundle identifier is frozen at `com.adamzvada.mirrorrelay`. Changing the
bundle identifier or Developer ID team after release creates a new macOS code
identity and forces users to grant privacy permissions again.

- Use an Apple Development identity for repeatable local development grants.
- Use one Developer ID Application identity for every public release.
- Never publish an ad-hoc build.
- Sign nested helpers before signing the outer app.
- Keep hardened runtime and secure timestamps enabled.

List available identities:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials in Keychain rather than a source file or shell
history:

```sh
xcrun notarytool store-credentials mirror-relay-notary
```

## Local package

```sh
npm run package:app
npm run verify:package
```

This creates an ad-hoc signed development bundle at `dist/Mirror Relay.app`.
Its identity changes when the code changes, so it is not suitable for testing
permission persistence across upgrades.

## Public release

```sh
export MIRROR_RELAY_SIGN_IDENTITY="Developer ID Application: …"
export MIRROR_RELAY_NOTARY_PROFILE="mirror-relay-notary"
npm run package:release
```

The release pipeline:

1. builds the Swift app and protocol-only helper;
2. signs the helper and outer app inside-out;
3. verifies layout, hardened runtime, versions, and Developer ID team;
4. notarizes and staples the app;
5. creates a compressed DMG with an `/Applications` shortcut;
6. signs, notarizes, staples, and Gatekeeper-checks the DMG;
7. writes `Mirror Relay-<version>.dmg.sha256`.

App notarization happens before DMG creation so the copy inside the disk image
also carries a stapled ticket. Release packaging fails before modifying an
artifact when credentials or the Developer ID identity are missing. The DMG is
built and validated under a temporary name, then atomically replaces the public
artifact only after every release check succeeds.

## Release acceptance

Before publishing a version:

- run `npm run check`;
- run `npm run test:smoke` against the exact installed build;
- run `npm run test:device` with the paired physical iPhone;
- install the DMG on a clean Mac account and confirm Gatekeeper acceptance;
- grant both permissions once, relaunch, and verify `mirror-relay doctor`;
- update from the previous signed version and confirm permissions persist;
- reboot the Mac and confirm launch-at-login plus `open → observe → act → close`.

The project currently releases arm64. Do not claim Intel support until a
Universal 2 build has been exercised on an Intel Mac with Apple’s T2 chip.
