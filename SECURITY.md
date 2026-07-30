# Security

## Supported version

Security fixes are applied to the latest release only.

## Boundary

Mirror Relay is intentionally local:

- the API listens only on `127.0.0.1`;
- phone observation and control require local authentication;
- no cloud, LAN, USB test server, or remote tunnel is included;
- the app does not bypass Apple security or handle passcodes.

Anyone who controls the same macOS account can potentially invoke the installed
CLI and operate the paired phone. Lock the Mac when it is unattended and do not
proxy port 8747.

## Reporting

Do not include phone screenshots, tokens, credentials, or private message
content in a report. Provide the Mirror Relay version, macOS version, a minimal
reproduction, and sanitized logs to the project owner through a private channel.
