# Packaging

Phone Use is a Swift menu app with one embedded Swift CLI. JavaScript is used
only for the local dashboard and tests; npm is the task runner, not the runtime.

## Developer package

    npm ci
    npm run package:app

This creates dist/Phone Use.app and verifies its bundle layout, protocol helper,
framework links, hardened runtime, architecture, and signatures.

Use npm run package:dev when a stable Apple Development or local development
identity is available. Run npm run signing:doctor to inspect the selected
identity.

## Distribution

The release scripts can create a signed DMG and render a Homebrew Cask, but
version 0.10 is not an end-user release because the physical-device backend is
not validated. Do not publish an artifact that implies phone control works.

Developer ID distribution additionally requires notarization credentials. See
scripts/package-release.sh for the required environment variables.

The package must not contain Apple developer components, private frameworks,
device support images, pairing records, tokens, or captured frames.
