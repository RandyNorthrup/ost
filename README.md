<p align="center"><img src="docs/banner.png" alt="OST banner: the OST logo and a mouse whose body is a computer mouse, with a USB cable for a tail, sniffing a wedge of cheese" width="100%"></p>

# OST

**OST is a native Linux clone of the Microsoft Teams desktop app for
Windows.** It looks and works like Teams, one to one: the same app bar,
chat list, conversations, channels, calendar, call and meeting windows,
settings and dialogs, measured from Teams itself. Only the name and the
logo differ. It is written in Rust with a Qt Quick interface, has its own
calling and media engine, and also includes the original terminal client,
`teams-cli`.

OST is an independent open-source project. It is **not affiliated with,
endorsed by or supported by Microsoft.** You sign in with your own Microsoft
work or school account.

*Ost* means cheese in Danish.

![OST: a group chat with formatting, a file, reactions and a code block](docs/screenshots/chat.png)

**Documentation:** the [OST wiki](https://github.com/RandyNorthrup/ost/wiki)
has installation, a feature tour with screenshots, configuration,
troubleshooting and the list of differences from Teams.

## Features

- **Chat:** 1:1, group and meeting chats with Teams' formatting, code
  blocks, emoji, GIFs, reactions, files from your computer or OneDrive,
  Loop components, video clips, scheduled messages, @mentions, read
  receipts, drafts, find in chat and search.
- **Teams and channels:** posts and threads layouts, replies, announcements,
  editing posts in Teams' post composer, followed threads, channel tabs
  (Shared, Page, Notes, apps), shared and private channels, managing teams
  and channels.
- **Copilot** (with a Microsoft 365 Copilot license): in chats, meeting chats
  and channel threads, and Write with Copilot in the message box.
- **Activity:** Teams' activity feed, live and synced with Teams.
- **Calendar:** day, work week, week and month views, event cards, RSVP,
  Teams' scheduling form, Outlook's event form for your events and
  invitations (series edits and cancels, time suggestions, the body
  editor's tools), Meet now and Join with an ID.
- **Calls and meetings:** 1:1 and group calls, meetings with video and
  background effects, screen and window sharing, raise hand, reactions,
  live captions, recording and transcripts, breakout rooms, town halls and
  webinars, hold, transfer and park, voicemail, Meeting Recaps and audio
  recaps.
- **Files:** OneDrive (Home, My files, Shared, Libraries, Recycle bin),
  channel files, previews, sharing, and Teams' cloud file picker.
- **Apps:** Teams' app bar and Store; People, Events and Meeting Recaps drawn
  natively; Planner, OneNote, Whiteboard, Copilot and other apps hosted as
  Teams hosts them.
- **Settings, notifications, presence:** Teams' Settings pages synced with
  your account, Teams' notification banners with quick reply, status and
  status messages, light, dark and high-contrast themes, Teams' keyboard
  shortcuts (Ctrl+. lists them), built-in Help (F1).
- **Teams Rooms:** run OST as a Teams Rooms device, cast to a room, join
  with a room's audio, and control a room from your laptop (Control Room
  System).
- **Translations:** every Teams app language, with Teams' own strings
  downloaded on first use (none of Microsoft's translations are in this
  repository).

<table>
  <tr>
    <td><img src="docs/screenshots/meeting.png" alt="A meeting with video, a raised hand and the People pane"></td>
    <td><img src="docs/screenshots/calendar.png" alt="The calendar's work week view"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/channel.png" alt="A channel post with replies"></td>
    <td><img src="docs/screenshots/activity-dark.png" alt="Activity and a chat in the dark theme"></td>
  </tr>
</table>

What OST knowingly does differently from Teams (Linux-specific sign-in, the
desktop's screen-share picker, feedback going to GitHub, no telemetry and
so on) is listed in
[Differences from Teams](https://github.com/RandyNorthrup/ost/wiki/Differences-from-Teams).

## Install

Every [release](https://github.com/RandyNorthrup/ost/releases/latest) has
native packages built against each distribution's own Qt 6, FFmpeg and
WebRTC audio processing, a Flatpak bundle, and an AppImage for everything
else. Each package has the desktop app `ost-desktop` (menu entry **OST**)
and the terminal client `teams-cli` (its own package for .deb and .rpm).
Check your download against the release's `SHA256SUMS`
(`sha256sum -c SHA256SUMS --ignore-missing`).

| System | Download | Install |
| --- | --- | --- |
| Ubuntu 26.04 | `ost-desktop_<version>-1.ubuntu26.04_amd64.deb` | `sudo apt install ./ost-desktop_*.ubuntu26.04_amd64.deb` |
| Debian testing (forky) | `ost-desktop_<version>-1.debian.forky_amd64.deb` | `sudo apt install ./ost-desktop_*.debian.forky_amd64.deb` |
| Fedora 45 | `ost-desktop-<version>-1.fc45.x86_64.rpm` | `sudo dnf install ./ost-desktop-*.fc45.x86_64.rpm` |
| openSUSE Tumbleweed | `ost-desktop-<version>-1.suse.tw.x86_64.rpm` | `sudo zypper install --allow-unsigned-rpm ./ost-desktop-*.suse.tw.x86_64.rpm` |
| Arch Linux | AUR `ost` / `ost-bin` (coming soon) | |
| Any, with Flatpak | `OST-<version>-x86_64.flatpak` | `flatpak install --user ./OST-*-x86_64.flatpak` (with the Flathub remote set up, for the KDE runtime) |
| Any, glibc 2.43+ | `OST-<version>-x86_64.AppImage` | `chmod +x OST-*-x86_64.AppImage && ./OST-*-x86_64.AppImage` |

Add `teams-cli_*.deb` or `teams-cli-*.rpm` to the same command for the
terminal client. apt, dnf and zypper pull in the libraries OST needs;
removing the package (`sudo apt remove ost-desktop`, `sudo dnf remove
ost-desktop`) removes it again. Fedora's and openSUSE's own FFmpeg leave out
some patented codecs; if a video clip doesn't play, install the full FFmpeg
from RPM Fusion or Packman.

To add the AppImage to your app menu, use the release's
`ost-<version>-linux-x86_64.tar.gz` (the same AppImage with the install
scripts):

```bash
tar xf ost-*-linux-x86_64.tar.gz
cd ost-*-linux-x86_64
sh packaging/install-user.sh ./OST-*-x86_64.AppImage   # ~/.local/bin/ost-desktop, menu entry and icon
ost-desktop
```

**Supported systems:** 64-bit x86 Linux on Wayland or X11. Your system
provides the graphics drivers, PipeWire for audio, a Secret Service keyring
(GNOME Keyring or KWallet) and, for screen sharing, xdg-desktop-portal with
your desktop's backend; the AppImage also needs glibc 2.43 or newer and FUSE
3 (`fuse3`). On other systems, build from source as below. More in
[Installation](https://github.com/RandyNorthrup/ost/wiki/Installation).

On first start OST shows Microsoft's sign-in page; sign in with your work or
school account. Settings ▸ About OST checks GitHub for newer releases.

**Bluetooth headsets:** mute works out of the box. Answering and ending
calls with the headset's button needs a one-time PipeWire setup:
`sh /usr/share/ost-desktop/install-hfp-calls.sh` with the .deb or .rpm, or
`sh packaging/install-hfp-calls.sh` from the tarball (it asks before
changing anything that needs `sudo`; `--uninstall` undoes it; not available
in the Flatpak). See
[Bluetooth headsets](https://github.com/RandyNorthrup/ost/wiki/Bluetooth-headsets).

## Build from source

Requirements: Rust stable (edition 2024), Qt 6.9 or newer with Qt Quick,
Quick Controls, Multimedia, WebEngine and the shader tools, a C++ compiler,
CMake, FFmpeg's development libraries, the ALSA and PipeWire development
files, clang, NASM, pkg-config, and the OpenSSL and WebRTC audio
processing (`webrtc-audio-processing-1`) development files.

```bash
# Arch
sudo pacman -S qt6-base qt6-declarative qt6-svg qt6-multimedia qt6-webengine qt6-shadertools ffmpeg alsa-lib cmake nasm \
  pipewire clang xdg-desktop-portal openssl webrtc-audio-processing-1 pkgconf
# Debian / Ubuntu
sudo apt install qt6-base-dev qt6-declarative-dev qml6-module-qtquick-controls \
  qml6-module-qtquick-window qml6-module-qtquick-shapes qml6-module-qtquick-effects qml6-module-qtquick-dialogs libqt6svg6 qml6-module-qtmultimedia qt6-webengine-dev qml6-module-qtwebengine qt6-shader-baker \
  libavfilter-dev libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
  libasound2-dev cmake nasm libpipewire-0.3-dev clang xdg-desktop-portal \
  libssl-dev libwebrtc-audio-processing-dev pkg-config

cargo build --release -p ost-desktop       # target/release/ost-desktop
desktop/packaging/install-user.sh          # installs target/release/ost-desktop for your user
```

The C++ parts are heavy; on machines with little memory use
`cargo build -j 2 --release -p ost-desktop`. To package your build as an
AppImage, also build `teams-cli` (`cargo build --release --bin teams-cli
--features audio`) and run `sh desktop/packaging/build-appimage.sh <version>`.
`desktop/packaging/build-deb.sh` and `build-rpm.sh` build the .deb and .rpm
packages on the distribution they are for (`--deps` installs the build
dependencies first); `.github/workflows/release.yml` builds every package
for a release. More in
[Building from source](https://github.com/RandyNorthrup/ost/wiki/Building-from-source)
and [docs/desktop.md](docs/desktop.md).

## Terminal client

`teams-cli` is OST's terminal client: a full-screen terminal interface for
teams, channels and chats, plus commands for scripts. It shares the engine,
account profiles and sign-in storage with the desktop app.

![The terminal client](docs/screenshots/tui.png)

```bash
./OST-*-x86_64.AppImage teams-cli tui                    # from the AppImage, or build it:
cargo build --release --bin teams-cli                    # or --features audio for calls with sound
teams-cli login            # device-code sign-in (skipped when already signed in)
teams-cli tui              # the terminal interface (? for its keys)
teams-cli chats            # recent chats and their ids
teams-cli read <chat-id> --limit 20
teams-cli send --to <chat-id> "Hello from the terminal"
teams-cli teams            # teams and channels
teams-cli presence --set busy
teams-cli call-test --echo --duration 20                 # test call with Teams' echo bot
```

`teams-cli --help` lists every command:

```
login      Authenticate with Microsoft Teams (--force to sign in again)
logout     Log out and clear cached credentials
status     Show current authentication status
chats      List recent chats (--limit N, default 20)
read       Read messages from a chat (<chat-id>, --limit N)
send       Send a message (--to <chat-id> <message>)
teams      List joined teams and their channels
whoami     Show current user info (verify auth works)
trouter    Connect to Trouter WebSocket push service
presence   Get/set presence status (--set available|busy|dnd|away|offline)
call-test  Place a test call (--echo, --thread <id>, --duration N (default 15),
           --record, --tone, --camera, --display)
mic-test   Test microphone capture (builds with the audio feature)
cam-test   Test camera capture (builds with the video-capture feature)
tui        Launch the terminal user interface
```

See [Terminal client](https://github.com/RandyNorthrup/ost/wiki/Terminal-client).

## Configuration

Settings live in OST's Settings (Ctrl+,). On disk: `~/.config/ost/desktop.json`
(this computer's settings), `~/.config/teams-cli/config.toml` (account
settings, no secrets), the log in `~/.local/state/ost/ost-desktop.log`, and
caches under `~/.cache/ost/`. Sign-in tokens are kept in the system keyring
(Secret Service); without one, or with `OST_NO_KEYRING=1`, they go to
`config.toml`, readable only by you. `OST_PROFILE=<name>` runs another
account. All files and environment variables:
[Configuration](https://github.com/RandyNorthrup/ost/wiki/Configuration).

## Testing

```bash
cargo test --workspace     # unit tests: engine, desktop backend, video effects
just check                 # rustfmt check, clippy, and compile the tests
just e2e                   # terminal client end-to-end tests (needs a signed-in test account)
```

The desktop app is also its own end-to-end test driver: given a PNG path and
a test flag it drives itself against the signed-in account, captures
pictures and quits. Use a test account; these tests send real messages and
schedule real meetings. The flags are listed in
[docs/desktop.md](docs/desktop.md#test-harness).

## Documentation

- [OST wiki](https://github.com/RandyNorthrup/ost/wiki): installation, feature tour, configuration, troubleshooting, FAQ
- [docs/desktop.md](docs/desktop.md): the desktop app's features, environment variables, keyboard shortcuts and test harness
- [docs/spec](docs/spec): measured specifications of the Teams surfaces OST follows
- [docs/help](docs/help): the built-in Help articles
- [docs/architecture.md](docs/architecture.md), [docs/terminology_index.md](docs/terminology_index.md), [docs/GUIDs.md](docs/GUIDs.md): protocols and the engine

## Feedback and privacy

In OST, Settings and more ▸ Feedback (Report a problem, Give a compliment,
Suggest a feature) opens a pre-filled public issue or discussion on this
repository, which you review and submit yourself. OST has no telemetry and
sends nothing to the project. See [SUPPORT.md](SUPPORT.md) and
[PRIVACY.md](PRIVACY.md).

## Contributing

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) for how to
build, test and match a feature to Teams, and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Report security problems
privately as [SECURITY.md](SECURITY.md) describes, not in a public issue.

## Authors

- Randy Northrup
- Mark Ruvald Pedersen

OST grew out of Mark Ruvald Pedersen's [eisbaw/ost](https://github.com/eisbaw/ost).

## License

MIT License, see [LICENSE](LICENSE). Third-party assets and their licenses
are listed in [desktop/assets/NOTICE.md](desktop/assets/NOTICE.md) and
[desktop/THIRD-PARTY-NOTICES.md](desktop/THIRD-PARTY-NOTICES.md).

## Disclaimer

OST is an unofficial client, provided as is; use it at your own risk and
within your organization's policies. It is not affiliated with, endorsed by
or supported by Microsoft. Microsoft, Microsoft Teams, Microsoft 365,
OneDrive, Outlook, Loop and Copilot are trademarks of the Microsoft group of
companies.

## Related projects

- [purple-teams](https://github.com/EionRobb/purple-teams/): Teams plugin for libpurple (Pidgin, Finch, etc.)
