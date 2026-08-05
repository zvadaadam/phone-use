# Phone Use Packaging

Phone Use ships as one native, menu-bar macOS app. The main Swift executable
owns Screen Recording and Accessibility consent. Its embedded Swift CLI is a
loopback protocol client and must never perform capture or input itself.

```text
Phone Use.app/
└── Contents/
    ├── MacOS/Phone Use
    ├── Helpers/phone-use
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

- Prefer Apple Development for repeatable local development grants.
- Use `Phone Use Local Development`, a self-signed Code Signing identity,
  only as a permission-stable local fallback.
- Continue accepting a pinned `Mirror Relay Local Development` identity for
  upgrades from the pre-rebrand app; do not rotate it automatically.
- Use one Developer ID Application identity for every public release.
- Never publish an ad-hoc build.
- Sign nested helpers before signing the outer app.
- Keep hardened runtime enabled; require secure timestamps for Developer ID
  releases.

## Permission-stable development builds

Do not install an ad-hoc rebuild over an app that already has Screen Recording
or Accessibility grants. An ad-hoc signature's designated requirement is its
exact CDHash, so every changed binary is a different TCC identity.

Prefer a stable identity from **Xcode → Settings → Accounts**: select your team,
open **Manage Certificates**, then choose **+ → Apple Development**. When the
Personal Team cannot issue another certificate, create a local-only identity in
**Keychain Access → Certificate Assistant → Create a Certificate**:

- name: `Phone Use Local Development`;
- identity type: **Self-Signed Root**;
- certificate type: **Code Signing**.

The packager pins one exact certificate SHA-1 on first use. It preserves the
installed app's available signer first, then accepts one unambiguous Apple
Development identity or that exact local identity:

```sh
npm run signing:doctor
npm run package:dev
```

The ignored `.phone-use/signing-identity-sha1` file is the local pin. Later
builds fail if it disappears from Keychain instead of choosing a different
identity. Deliberately removing the pin opts into a new selection and can
require one new permission grant. Keep the bundle identifier and certificate
unchanged. The self-signed channel proves update continuity only on the Mac
containing its private key; it is not trusted for distribution.

On the first build after the rename, the packager atomically copies a valid pin
from `.mirror-relay/signing-identity-sha1` when the new pin does not exist. The
runtime likewise copies the existing token from `Application Support/Mirror
Relay` into `Application Support/Phone Use` without rotating it. Both migrations
record one-time completion, so deliberately deleting the new pin or token never
resurrects the retired legacy value.

List available identities:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials in Keychain rather than a source file or shell
history:

```sh
xcrun notarytool store-credentials phone-use-notary
```

## Local package

```sh
npm run package:app
npm run verify:package
```

This reuses the pinned development certificate. On first use it applies the
selection rules above; otherwise it creates an ad-hoc artifact at `dist/Phone
Use.app` and prints a warning. The ad-hoc result is suitable for package
verification only, not permission persistence testing. Use `npm run
package:dev` for an installable development build.

## Public release

```sh
export PHONE_USE_SIGN_IDENTITY="Developer ID Application: …"
export PHONE_USE_NOTARY_PROFILE="phone-use-notary"
npm run package:release
```

The release pipeline:

1. builds the Swift app and protocol-only helper;
2. signs the helper and outer app inside-out;
3. verifies layout, hardened runtime, versions, and Developer ID team;
4. notarizes and staples the app;
5. creates a compressed DMG with an `/Applications` shortcut;
6. signs, notarizes, staples, and Gatekeeper-checks the DMG;
7. writes `Phone-Use-<version>.dmg.sha256` and renders a checksum-pinned Cask
   at `dist/homebrew/Casks/phone-use.rb`.

App notarization happens before DMG creation so the copy inside the disk image
also carries a stapled ticket. Release packaging fails before modifying an
artifact when credentials or the Developer ID identity are missing. The DMG is
built and validated under a temporary name, then atomically replaces the public
artifact only after every release check succeeds.

The release artifact uses a URL-safe filename so the same bytes can be uploaded
to a `phone-use-v<version>` release in the dedicated
`zvadaadam/homebrew-tap` repository and consumed by Homebrew without URL
rewriting. Publish the generated Cask from that tap as well. This keeps the
source repository private while giving ordinary Homebrew clients one public
binary owner. For a local installation proof before publishing, render a
second Cask with an exact file URL:

```sh
PHONE_USE_CASK_LOCAL=1 \
  scripts/render-cask.sh \
  "dist/Phone-Use-<version>.dmg" \
  "dist/homebrew-local/Casks/phone-use.rb"
```

## Release acceptance

Before publishing a version:

- run `npm run check`;
- run `npm run test:smoke` against the exact installed build;
- run `npm run test:device` with the paired physical iPhone;
- run `npm run test:focus` with a browser frontmost;
- install the DMG on a clean Mac account and confirm Gatekeeper acceptance;
- grant both permissions once, relaunch, and verify `phone-use doctor`;
- update from the previous signed version and confirm permissions persist;
- reboot the Mac and confirm launch-at-login plus `open → observe → act → close`.

The project currently releases arm64. Do not claim Intel support until a
Universal 2 build has been exercised on an Intel Mac with Apple’s T2 chip.
