# Security policy

## Supported versions

Security fixes go into the latest release only. Update to the newest
[release](https://github.com/RandyNorthrup/ost/releases/latest) before you
report a problem; anything older is not patched.

## Reporting a vulnerability

Please report security problems privately, not in a public issue or
discussion. Use GitHub's private vulnerability reporting:

1. Open the repository's [Security tab](https://github.com/RandyNorthrup/ost/security).
2. Choose **Report a vulnerability**
   ([direct link](https://github.com/RandyNorthrup/ost/security/advisories/new)).
3. Describe the problem: the OST version (Settings ▸ About, or
   `ost-desktop --version`), your distribution, the steps to reproduce it, and
   what an attacker could do with it.

Only the maintainers can see the report. We reply in the report, work on a
fix there, and publish a security advisory with the release that fixes it.
You're credited unless you'd rather not be.

Please don't put sign-in tokens, passwords, or other people's messages and
data in a report. If a log is needed, remove tokens and personal details
first.

## Scope

This policy covers OST's own code: the desktop app (`ost-desktop`), the
terminal client (`teams-cli`), the engine, and the packages published on
this repository's releases page. Vulnerabilities in Microsoft Teams or
Microsoft 365 services go to Microsoft through the
[Microsoft Security Response Center](https://msrc.microsoft.com/report).
Problems in a distribution's Qt, OpenSSL or other system libraries go to
that project or distribution.
