# Privacy

OST is a Microsoft Teams client. It talks to the same services Teams does,
only for your signed-in account, and only to do what you ask it to. Your
organization's Microsoft 365 policies apply as they do in Teams.

OST has no telemetry, no analytics and no crash reporting, and sends
nothing to the OST project. The few things it fetches from outside
Microsoft are listed below.

## Who OST talks to

**Microsoft, for your account** (all over HTTPS):

- Teams and Skype services: `teams.microsoft.com`, `teams.cloud.microsoft`,
  `teams.live.com`, `*.trouter.teams.microsoft.com` (notifications),
  `*.skype.com` (registrar, chat, presence, calls), `ic3.teams.office.com`,
  `config.teams.microsoft.com` (Teams' feature settings).
- Sign-in: `login.microsoftonline.com`, `login.microsoft.com`.
- Microsoft Graph: `graph.microsoft.com`.
- Microsoft 365: `substrate.office.com` (search), `outlook.office.com`,
  your organization's `*.sharepoint.com` (files, OneDrive),
  `*.officeapps.live.com` (Office viewers), Loop, Whiteboard and Copilot.
- Microsoft's content networks for Teams' own resources:
  `statics.teams.cdn.office.net` (backgrounds, Teams' translated strings),
  `teams.public.onecdn.static.microsoft` (emoji), `res.public.onecdn.static.microsoft`
  (video clip music), `res.cdn.office.net`.
- Calls and meetings connect to Microsoft's media relays and servers that
  Teams' services hand out for each call.

The Microsoft 365 web apps that OST shows inside its window (as Teams does)
run Microsoft's own web code, which can send Microsoft its usual web-app
telemetry. OST neither adds to it nor blocks it.

**Others:**

- **GitHub** (`api.github.com`): OST checks for a new OST release 20 seconds
  after it starts and then once a day, as Teams checks for updates. GitHub
  sees your IP address and OST's version (the request's user agent,
  `ost/<version>`); nothing else is sent.
- **Giphy** (`media*.giphy.com`): GIF search goes through Teams' service,
  but the GIF pictures load straight from Giphy while the GIF picker is
  open or a message shows a GIF, as in Teams. With **Settings ▸ Privacy ▸
  Optional connected experiences** off, the picker has no GIFs and link
  previews are off too.
- **Hugging Face** (`huggingface.co`) and **GitHub** (`github.com`): two
  models download the first time you use the feature that needs them, and
  are checked against a pinned SHA-256: sign language detection (when you
  turn it on in a meeting) and Voice isolation (when it has a voice
  profile). The background effects model is part of OST.
- **The Diagnostic Data Viewer**, only when you turn it on, streams to the
  address you enter.

Links to other sites (LinkedIn, Clipchamp, app publishers' pages) open in
your browser.

## Where the sign-in lives

OST keeps your sign-in tokens (access, refresh, Skype, Graph and calling
tokens) as one entry in your desktop keyring through the Secret Service
(GNOME Keyring, KWallet, KeePassXC): service `ost`, account `teams-tokens`
(`teams-tokens:<profile>` for another account, with `@io.github.RandyNorthrup.ost`
added in the Flatpak). Any app of yours that can unlock the keyring can read
it, as with any Secret Service secret.

Without a working keyring (or with `OST_NO_KEYRING` set), the tokens are
written to `~/.config/teams-cli/config.toml`, readable only by you (mode
0600) but not encrypted. Set up a keyring to avoid that.

Signing in also leaves Microsoft's sign-in cookies in OST's web profile
(`~/.local/share/OST/QtWebEngine/ost-apps`), which the embedded Microsoft
365 apps use too; it is shared by all of OST's accounts.

Signing out deletes the tokens from the keyring and removes the account
from OST's account list. Today it leaves the web profile, the caches, the
drafts and the log on your computer; delete the folders below to remove
them.

## What OST stores on your computer

Everything is in your home folder, and readable only by you where the
content is personal:

| Where | What |
| --- | --- |
| `~/.config/teams-cli/` | `config.toml` (your tenant, name, sign-in address, service endpoints and licenses; the tokens only without a keyring), `accounts.json` (your signed-in accounts), `hub.json` and `hub-pins.json` (each account's unread counts and recent chats, for the account switcher), `calling-endpoint-id` (a random ID for this device's calls). Other accounts are in `profiles/<name>/`. |
| `~/.config/ost/` | `desktop.json` (OST's settings), `ddv.json` (Diagnostic Data Viewer). |
| `~/.config/autostart/ost-desktop.desktop` | Only while **Auto-start OST** is on. |
| `~/.local/state/ost/` | The log (`ost-desktop.log`), unsent drafts and messages (`drafts.json`, `outbox.json`), and the list of files you downloaded with OST (`downloads.json`). |
| `~/.cache/ost/` | Message images, profile pictures, video clips, recordings, file thumbnails and previews, emoji, Teams' translated strings and feature settings, call backgrounds, downloaded models, and feedback screenshots. Safe to delete; OST fetches what it needs again. |
| `~/.local/share/ost/backgrounds/uploads/` | Call backgrounds you added. |
| `~/.local/share/OST/QtWebEngine/ost-apps`, `~/.cache/OST/QtWebEngine/ost-apps` | The web profile: cookies, site storage and cache of the sign-in and the embedded Microsoft 365 apps. |
| Your Downloads folder | Files you download (Settings can change the folder). |

The research variables `OST_TROUTER_DUMP_DIR` and `OST_DUMP_RTP` write
message contents or call data to disk when you set them; they're for
protocol research on test accounts only.

The log records what OST does at the `info` level (sign-in and call
states, the services it called, errors). It's written to keep to shapes
and states, not message text or tokens, but it isn't masked on disk. It is
rewritten each time OST starts (with **Extended diagnostics** on, it keeps
up to 64 MB across starts). Help ▸ **Collect Support Files** copies it to a
folder on your Desktop as it is; feedback that shares log lines masks
names, addresses, message text and tokens first (see below). Look through
the log before you send it to anyone.

To remove everything: delete the folders above and the `ost` entry in your
keyring (Seahorse, KWalletManager or your keyring's app). In the Flatpak,
the same folders are under `~/.var/app/io.github.RandyNorthrup.ost/`.

## The Flatpak's permissions

The Flatpak asks only for what OST uses; each permission is explained in
its manifest (`desktop/packaging/flatpak/io.github.RandyNorthrup.ost.yml`):

- **Network**: Teams' services, calls and the embedded web apps.
- **Wayland, or X11** where there's no Wayland session.
- **All devices**: cameras (V4L2) and headsets' call buttons, lights and
  ring (HID: Flatpak has no narrower permission for HID devices); the GPU
  comes with it. Cameras will come through the camera portal instead.
- **PipeWire and PulseAudio**: microphones, speakers, ringtones and the
  screen-share streams the desktop's portal hands over.
- **Downloads folder** only: downloaded files go there, as in Teams.
  Nothing else in your home folder is visible to it.
- **Session bus names**: notifications, the keyring (Secret Service), the
  tray icon and launcher badge, and KDE's KWin (keeping OST's own windows
  out of screen shares).
- **System bus names**, to read: logind (away when the screen locks),
  NetworkManager (work location from the Wi-Fi network's name), BlueZ (a
  Bluetooth scan for nearby Teams Rooms while the pre-join screen looks for
  them).

Screen sharing, opening links and picking files go through the desktop
portals, which ask you each time.

## Optional system changes

OST's packages install their files under `/usr` like any package and change
nothing else. Only one optional setup changes your system: Bluetooth
headset answer and hang-up buttons on stock PipeWire
(`sh /usr/share/ost-desktop/install-hfp-calls.sh`; in the AppImage
tarball, `packaging/install-hfp-calls.sh`). Before it changes anything it
lists every change and asks; `--dry-run` only lists them:

1. `~/.config/wireplumber/wireplumber.conf.d/ost-hfp-calls.conf`: PipeWire's
   Bluetooth gateway hands a headset's answer and hang-up to OST's calls
   (never to a real modem's). WirePlumber is restarted.
2. `/etc/dbus-1/system.d/ost-hfp-calls.conf` (with `sudo`): your user may
   own ModemManager's name on the system bus, where OST offers its calls to
   PipeWire. Nobody else gains anything.
3. ModemManager, only if it runs without a modem and only with your
   separate yes (or `--disable-modemmanager`): it's stopped and disabled,
   so OST can take its name. A modem plugged in later isn't detected until
   it's enabled again. With a modem, ModemManager is never touched.

`--uninstall` puts everything back as it was: files it replaced are
restored, the ones it added removed, and ModemManager enabled and started
again if it was. The headset's mute button works without any of this.

## Feedback

Feedback ▸ Report a problem and Give a compliment (the same forms Teams uses
to send feedback to Microsoft) open a **public** issue on
[the OST GitHub repo](https://github.com/RandyNorthrup/ost/issues).
OST fills the form in and opens it in your browser; it doesn't post
anything itself. You can review and edit it, and you decide whether to
submit it, under your own GitHub account.

What the issue holds:

- What you wrote, and the files or screenshots you add to it on GitHub.
- OST's version, your operating system, and where in OST you sent the
  feedback from.
- If you answer **Yes, share**: the most recent lines of OST's log. Names,
  e-mail addresses, phone numbers, chat and message text, and tokens are
  masked first.
- Your answer to **May we contact you about your feedback?** Replies come
  on the issue. Your e-mail address is never added.

Feedback ▸ Suggest a feature opens the repo's
[Ideas](https://github.com/RandyNorthrup/ost/discussions/categories/ideas)
discussions. Like Microsoft's feedback portal, these are public.

Help (F1) is bundled with OST and works offline.
