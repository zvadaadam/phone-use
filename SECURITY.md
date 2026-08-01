# Security

## Supported version

Security fixes are applied to the latest release only.

## Boundary

Mirror Relay is intentionally local:

- the API listens only on `127.0.0.1`;
- requests with any other HTTP `Host` are rejected to prevent DNS rebinding;
- every route, including liveness and static assets, requires local
  authentication or a one-time bootstrap credential;
- no cloud, LAN, USB test server, or remote tunnel is included;
- the app does not bypass Apple security or handle passcodes.

Anyone who controls the same macOS account can potentially invoke the installed
CLI and operate the paired phone. Lock the Mac when it is unattended and do not
proxy port 8747.

The Screen Recording and Accessibility grants belong only to the signed app.
The embedded CLI is a protocol client, does not link ScreenCaptureKit, and
rejects incompatible or stale broker versions before issuing commands.

## Reporting

Do not include phone screenshots, tokens, credentials, or private message
content in a report. Provide the Mirror Relay version, macOS version, a minimal
reproduction, and sanitized logs to the project owner through a private channel.
