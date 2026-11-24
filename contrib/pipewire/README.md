# Bluetooth headset call buttons (PipeWire)

Teams answers, rejects and ends calls from a Bluetooth (HFP) headset's
buttons because Windows' Bluetooth service, the HFP audio gateway, hands the
headset's ATA and AT+CHUP to the VoIP call coordinator that Teams reports its
calls to. On Linux the gateway is PipeWire's native HFP backend. It rings the
headset for the calls of a ModemManager modem and gives the headset's
commands to them, looking for that modem at ModemManager's name on the
system bus. PipeWire's `org.pipewire.Telephony` service doesn't cover it: it
serves the other direction, with PipeWire as the hands-free side of a phone.

OST offers its calls as such a modem (ModemManager's Modem, Modem3gpp, Voice
and Call interfaces). There are two ways to let PipeWire's gateway find it.

## Stock PipeWire (the default way)

`desktop/packaging/install-hfp-calls.sh` sets it up on an unmodified
PipeWire/WirePlumber:

- `~/.config/wireplumber/wireplumber.conf.d/ost-hfp-calls.conf` sets
  `bluez5.hfphsp-backend-native-modem = "ost"`, so the gateway looks for a
  modem (it's `none` by default) and takes only OST's (its `Device`), never a
  real one.
- `/etc/dbus-1/system.d/ost-hfp-calls.conf` (installed with sudo) lets your
  user own `org.freedesktop.ModemManager1` on the system bus and send the
  gateway's few calls to it (the same ones ModemManager's own policy allows
  everyone).
- ModemManager takes that name at boot and never gives it up. If it runs
  without a modem, the script stops and disables it after asking (`--yes`
  skips the question; `--uninstall` undoes everything and enables it again).
  With a modem it's left alone and the buttons stay unavailable.

OST holds the name only while it runs and has the headset's buttons (Teams'
"Transfer controls to this app"). It shows its modem only to your user's
PipeWire gateway (WirePlumber, checked by its D-Bus connection's user and
process): NetworkManager, GeoClue, fwupd and Plasma, which also read
ModemManager's name, see a ModemManager without modems. Only that gateway may
answer or end a call or read the caller's name, so other local users can't,
even where ModemManager's policy lets everyone call those methods.

What the policy grants: while ModemManager doesn't run, programs of your user
could pose as ModemManager to system services. NetworkManager ignores modems
without ports and lets the active local user configure networking anyway, so
this gives nothing beyond what the desktop user already has.

## Patched PipeWire (the other way)

`0001-bluez5-backend-native-allow-the-modem-on-the-session-bus.patch`
(against PipeWire master, ready to submit) adds
`bluez5.hfphsp-backend-native-modem-bus = "session"`. PipeWire's existing
ModemManager client then looks for the modem on the session bus, where OST
also offers it. No system bus policy and no change to ModemManager, but a
rebuilt libspa-bluez5 until the change is upstream. Enable it in WirePlumber
by copying `ost-hfp-modem.conf` to `~/.config/wireplumber/wireplumber.conf.d/`
and restarting WirePlumber.

## Without either

PipeWire's gateway never reads OST's modem. OST notices, logs why (no policy,
ModemManager holding the name, or WirePlumber not looking), and shows
nothing, as Teams shows nothing where the platform lacks call control. The
headset's mute works regardless: its microphone gain (AT+VGM) going to 0 and
back mutes and unmutes the call, and OST's own mute sets the gain to 0.
