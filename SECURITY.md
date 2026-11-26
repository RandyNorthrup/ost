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
data in a report. If a log is needed, remove personal details first (OST's
logs don't hold tokens, but check anyway).

## How OST protects your account

- **Tokens go only where they belong.** A request carries a Teams, Skype,
  IC3 or Graph token only when its address is HTTPS and its host is one of
  the Microsoft services that token is for (an exact allowlist matched on
  whole host labels); redirects off those services aren't followed. Card
  and preview pictures from other sites load without any credentials, and
  never over plain HTTP.
- **Token storage.** Tokens live in the system keyring (Secret Service).
  Without one OST keeps them in memory only; a file (0600, written
  atomically) is used only if you opt in (Settings ▸ Accounts and orgs ▸
  Stay signed in without a keyring, or `OST_NO_KEYRING=1`). Tokens an older
  OST wrote to the file move to the keyring once it works.
- **Embedded pages.** Camera, microphone, location and notifications go
  only to a hosted app's own pages (its declared valid domains) and only as
  its App permissions allow; any other origin is refused. Values OST puts
  into the pages it builds are serialized so they can't break out of their
  script. Each profile has its own web storage, and signing out clears it.
- **Logs and feedback.** Tokens, cookies and signed-address parameters are
  removed from every log line before it is written. Report a problem opens
  the issue form with only your text; logs are saved to a file you review
  and attach yourself.
- **No test hooks in releases.** The desktop test harness (launch flags,
  scripted steps, JavaScript injection) is compiled only with the
  `test-harness` cargo feature, which release packages don't enable; a
  release build refuses those flags, and CI checks it.

## Verifying a download

Every file on a release (the AppImage, the tarball, the .deb, .rpm and
.flatpak packages, and `SHA256SUMS`) has a GitHub build-provenance
attestation, signed through Sigstore. It proves the file was built by this
repository's release workflow (`.github/workflows/release.yml`) on
GitHub's runners from the tagged commit, and that it hasn't changed since.
Check one with the [GitHub CLI](https://cli.github.com/) (2.49 or newer):

```sh
gh attestation verify OST-0.3.0-x86_64.AppImage -R RandyNorthrup/ost
```

To also pin the workflow and the tag:

```sh
gh attestation verify OST-0.3.0-x86_64.AppImage -R RandyNorthrup/ost \
  --signer-workflow RandyNorthrup/ost/.github/workflows/release.yml \
  --source-ref refs/tags/v0.3.0 --deny-self-hosted-runners
```

`sha256sum -c SHA256SUMS --ignore-missing` in the download folder checks the
files against the checksums; on its own that only shows they weren't
damaged, so verify `SHA256SUMS` itself with `gh attestation verify` first.
Releases before 0.3.0 have checksums only.

The AUR packages are updated from the same release files: `ost-bin` checks
the AppImage against the SHA-256 recorded when the release was published,
and `ost` builds the tagged source.

## How the releases are built

- Each package is built in a container of the distribution it is for, from
  that distribution's signed package repositories.
- The workflows' GitHub Actions are pinned to commit SHAs, the Flatpak
  builder image to its digest.
- Every tool the build downloads is pinned to an exact version and checked
  against its SHA-256 before it runs: linuxdeploy, appimagetool and the
  AppImage runtime; linuxdeploy-plugin-qt is built from an exact commit
  (`desktop/packaging/build-appimage.sh`); `flatpak-cargo-generator.py` is
  fetched at an exact commit, and its Python dependencies are installed with
  `pip --require-hashes` from
  `desktop/packaging/flatpak/cargo-generator-requirements.txt`. The Flatpak
  runtimes come from Flathub, checked against Flathub's signing key, whose
  hash the workflow pins.
- Every crate comes from crates.io at the version and checksum in
  `Cargo.lock` (`--locked`).
- CI audits the dependencies on every push and pull request: `cargo audit`
  and `cargo deny` (RustSec advisories, licenses, sources). An advisory that
  can't be fixed yet is listed in `deny.toml` and `.cargo/audit.toml` with
  its reason and a date by which it's reviewed again.

## Data, tokens and system changes

[PRIVACY.md](PRIVACY.md) lists what OST stores and where, where the sign-in
tokens live, which hosts it talks to, the Flatpak's permissions, and the
optional system changes of the Bluetooth headset call setup
(`install-hfp-calls.sh`), which lists every change and asks before it makes
any, asks separately before touching ModemManager, and undoes all of it with
`--uninstall`.

## Scope

This policy covers OST's own code: the desktop app (`ost-desktop`), the
terminal client (`teams-cli`), the engine, and the packages published on
this repository's releases page. Vulnerabilities in Microsoft Teams or
Microsoft 365 services go to Microsoft through the
[Microsoft Security Response Center](https://msrc.microsoft.com/report).
Problems in a distribution's Qt, OpenSSL or other system libraries go to
that project or distribution.
