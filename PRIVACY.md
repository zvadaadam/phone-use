# Privacy

Phone Use keeps its API on IPv4 loopback and requires a 256-bit local token.
The dashboard exchanges a one-time bootstrap for an HttpOnly, SameSite=Strict
session cookie.

The current Device Hub placeholder receives no phone frames and sends no phone
input. When the backend is implemented, frames are intended to stay transient
in memory and be returned only to an authenticated local client. Phone Use must
not save frames, action text, pairing records, or device credentials by default.

An Internet relay is not implemented. Future remote access must use explicit
authentication, encrypted transport, revocation, and a clear owner-controlled
trust boundary. The loopback listener must never simply be exposed publicly.
