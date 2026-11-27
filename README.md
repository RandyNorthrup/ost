<p align="center"><img src="docs/banner.png" alt="OST banner: the OST logo and a mouse whose body is a computer mouse, with a USB cable for a tail, sniffing a wedge of cheese" width="100%"></p>

<p align="center">
  <b>The Microsoft Teams desktop app, rebuilt natively for Linux.</b>
</p>

<p align="center">
  <a href="https://github.com/RandyNorthrup/ost/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/RandyNorthrup/ost?style=flat-square&color=5B5FC7&label=release"></a>
  <a href="https://github.com/RandyNorthrup/ost/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/RandyNorthrup/ost/total?style=flat-square&color=2EA043&label=downloads"></a>
  <a href="https://github.com/RandyNorthrup/ost/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/RandyNorthrup/ost?style=flat-square&color=E3B341&label=stars"></a>
  <a href="https://github.com/RandyNorthrup/ost/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/RandyNorthrup/ost/ci.yml?branch=main&style=flat-square&label=CI"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/RandyNorthrup/ost?style=flat-square&color=8957E5"></a>
  <a href="https://github.com/sponsors/RandyNorthrup"><img alt="Sponsor on GitHub" src="https://img.shields.io/badge/sponsor-GitHub-DB61A2?style=flat-square&logo=githubsponsors&logoColor=white"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="https://github.com/RandyNorthrup/ost/wiki">Wiki</a> ·
  <a href="#development">Development</a> ·
  <a href="#sponsor">Sponsor</a>
</p>

OST looks and works like Teams for Windows, screen for screen: chat,
channels, calls and meetings, calendar, files and settings. It is written
in Rust with a Qt Quick interface and has its own calling and media engine,
so it runs as a real desktop app, not a web page in a window. Sign in with
your Microsoft work or school account.

<p align="center"><img src="docs/screenshots/chat.png" alt="A group chat in OST with reactions and a shared PDF" width="100%"></p>

## Install

Download your package from the
[latest release](https://github.com/RandyNorthrup/ost/releases/latest), then:

| System | Command |
| --- | --- |
| Ubuntu 26.04 | `sudo apt install ./ost-desktop_*.ubuntu26.04_amd64.deb` |
| Debian testing | `sudo apt install ./ost-desktop_*.debian.forky_amd64.deb` |
| Fedora 45 | `sudo dnf install ./ost-desktop-*.fc45.x86_64.rpm` |
| openSUSE Tumbleweed | `sudo zypper install --allow-unsigned-rpm ./ost-desktop-*.suse.tw.x86_64.rpm` |
| Flatpak | `flatpak install --user ./OST-*-x86_64.flatpak` |
| Any distribution | `chmod +x OST-*-x86_64.AppImage && ./OST-*-x86_64.AppImage` |

Arch Linux packages are coming to the AUR. OST runs on 64-bit x86 Linux
with Wayland or X11. Requirements, checksums, the terminal client package,
updating and uninstalling are covered in
[Installation](https://github.com/RandyNorthrup/ost/wiki/Installation).
Every release file has a build-provenance attestation: check one with
`gh attestation verify <file> -R RandyNorthrup/ost`
([Verifying a download](SECURITY.md#verifying-a-download)).

## Features

### Chat and channels

One-to-one, group and meeting chats with Teams' formatting, code blocks,
reactions, files, Loop components, video clips and scheduled messages.
Channels have Teams' posts and threads layouts, replies, announcements and
tabs.

<p align="center"><img src="docs/screenshots/channel.png" alt="A channel post with a reply in OST" width="100%"></p>

### Calls and meetings

Video calls and meetings with background effects, screen sharing, raised
hands, reactions, live captions, recording, breakout rooms, town halls and
webinars, plus call transfer, park and voicemail.

<p align="center"><img src="docs/screenshots/meeting.png" alt="A meeting in OST with video and a raised hand" width="100%"></p>

### Calendar

Day, work week, week and month views, RSVP, and Teams' scheduling form for
new meetings, with Meet now and Join with an ID.

<p align="center"><img src="docs/screenshots/calendar.png" alt="The work week view of OST's calendar" width="100%"></p>

### Copilot

With a Microsoft 365 Copilot license, Copilot works in chats, meetings and
channels, and helps you write messages.

<p align="center"><img src="docs/screenshots/copilot.png" alt="The Copilot pane next to a chat in OST" width="100%"></p>

### Also included

- **Files:** OneDrive, channel files, previews, version history and sharing.
- **Activity and notifications:** Teams' activity feed and notification
  banners with quick reply.
- **Apps:** Teams' app store, with Planner, OneNote, Whiteboard and other
  apps hosted the way Teams hosts them.
- **Settings:** every Teams settings page, synced with your account; light,
  dark and high-contrast themes; every Teams language.
- **Teams Rooms and devices:** room mode, casting to a room, and headset
  call controls over USB and Bluetooth.
- **Terminal client:** `teams-cli`, a full-screen terminal interface for
  chats and channels, plus commands for scripts.

The [wiki](https://github.com/RandyNorthrup/ost/wiki) documents every
feature with screenshots. Where OST deliberately differs from Teams, such as
sign-in on Linux, your desktop's screen-share picker and no telemetry, see
[Differences from Teams](https://github.com/RandyNorthrup/ost/wiki/Differences-from-Teams).

## Support and privacy

Questions and bug reports go to
[GitHub issues](https://github.com/RandyNorthrup/ost/issues). In the app,
Settings and more ▸ Feedback opens a pre-filled issue that you review and
submit yourself. OST has no telemetry and sends nothing to the project; see
[PRIVACY.md](PRIVACY.md). Report security problems privately as described
in [SECURITY.md](SECURITY.md).

## Development

OST builds with Rust stable and Qt 6.9 or newer:

```bash
cargo build --release -p ost-desktop
cargo test --workspace
```

The build dependencies for each distribution are listed in
[Building from source](https://github.com/RandyNorthrup/ost/wiki/Building-from-source).
Before opening a pull request, read [CONTRIBUTING.md](CONTRIBUTING.md) and
the [code of conduct](CODE_OF_CONDUCT.md). Architecture and protocol notes
live in [docs/](docs/).

## Sponsor

OST is built and maintained in spare time and is free for everyone. If it
saves you a browser tab every workday, you can help keep it going.

<p align="center">
  <a href="https://github.com/sponsors/RandyNorthrup"><img alt="Sponsor on GitHub" src="https://img.shields.io/badge/Sponsor_on_GitHub-DB61A2?style=for-the-badge&logo=githubsponsors&logoColor=white" height="36"></a>
  &nbsp;
  <a href="https://www.paypal.com/donate/?hosted_button_id=Q9VC7B42R7K82"><img alt="Donate with PayPal" src="https://img.shields.io/badge/Donate_with_PayPal-003087?style=for-the-badge&logo=paypal&logoColor=white" height="36"></a>
</p>

## Authors

<table>
  <tr>
    <td align="center"><a href="https://github.com/RandyNorthrup"><img src="https://github.com/RandyNorthrup.png?size=120" width="80" alt=""><br>Randy Northrup</a></td>
    <td align="center"><a href="https://github.com/eisbaw"><img src="https://github.com/eisbaw.png?size=120" width="80" alt=""><br>Mark Ruvald Pedersen</a></td>
  </tr>
</table>

OST grew out of Mark Ruvald Pedersen's [eisbaw/ost](https://github.com/eisbaw/ost).
*Ost* is Danish for cheese.

## License

MIT, see [LICENSE](LICENSE). Third-party assets are listed in
[NOTICE.md](desktop/assets/NOTICE.md) and
[THIRD-PARTY-NOTICES.md](desktop/THIRD-PARTY-NOTICES.md).

OST is an independent project, not affiliated with, endorsed by or
supported by Microsoft. Microsoft, Microsoft Teams, Microsoft 365, OneDrive,
Outlook, Loop and Copilot are trademarks of the Microsoft group of
companies.
