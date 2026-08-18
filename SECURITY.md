# Security

## Trust boundary

Phone Use is a single-user local agent bridge. The macOS account, signed app,
local API token, and paired physical device are trusted. Web pages, other local
processes, remote networks, and agent-generated action payloads are untrusted.

## Current protections

- IPv4 loopback-only listener;
- exact Host and Origin validation;
- bearer token in a mode-0600 user-owned file;
- no query-string authentication;
- one-time dashboard bootstraps;
- HttpOnly, SameSite=Strict browser sessions;
- one-megabyte request limit;
- normalized coordinate, text-size, shortcut, and frame-token validation;
- zero control capabilities until physical proof exists;
- no GUI-event transport or fallback;
- packaged binaries signed together and checked for retired framework links.

## Action boundary

Every future action must consume a fresh, one-shot token bound to the exact
observed device frame. A backend may report success only when device input was
delivered, a later device frame verifies the result, and Mac focus did not
change. Any ambiguity fails closed.

## Reporting

Do not include local tokens, pairing records, device identifiers, screenshots,
typed text, signing keys, or notarization credentials in an issue. Report
security problems privately to the repository owner.
