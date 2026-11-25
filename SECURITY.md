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

## Verifying a download

Every file on a release (the AppImage, the tarball, the .deb, .rpm and
.flatpak packages, and `SHA256SUMS`) has a GitHub build-provenance
attestation, signed through Sigstore. It proves the file was built by this
repository's release workflow (`.github/workflows/release.yml`) on
GitHub's runners from the tagged commit, and that it hasn't changed since.
Check one with the [GitHub CLI](https://cli.github.com/) (2.49 or newer):

```sh
gh attestation verify OST-0.2.2-x86_64.AppImage -R RandyNorthrup/ost
```

To also pin the workflow and the tag:

```sh
gh attestation verify OST-0.2.2-x86_64.AppImage -R RandyNorthrup/ost \
  --signer-workflow RandyNorthrup/ost/.github/workflows/release.yml \
  --source-ref refs/tags/v0.2.2 --deny-self-hosted-runners
```

`sha256sum -c SHA256SUMS --ignore-missing` in the download folder checks the
files against the checksums; on its own that only shows they weren't
damaged, so verify `SHA256SUMS` itself with `gh attestation verify` first.
Releases before 0.2.2 have checksums only.

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
