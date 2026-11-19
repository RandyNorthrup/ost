# Bluetooth headset call buttons (PipeWire)

Teams answers, rejects and ends calls from a Bluetooth (HFP) headset's
buttons because Windows' Bluetooth service, the HFP audio gateway, hands the
headset's ATA and AT+CHUP to the VoIP call coordinator that Teams reports its
calls to. On Linux the gateway is PipeWire's native HFP backend. It gives
those commands only to a ModemManager modem on the system bus, which an app
can't provide. PipeWire's `org.pipewire.Telephony` service doesn't cover it
either: it serves the other direction, with PipeWire as the hands-free side of
a phone.

`0001-bluez5-backend-native-allow-the-modem-on-the-session-bus.patch`
(against PipeWire master, ready to submit) adds
`bluez5.hfphsp-backend-native-modem-bus = "session"`. PipeWire's existing
ModemManager client then looks for the modem on the session bus. OST offers
its calls there as one modem, so the headset rings for an incoming call and
its answer and hang-up buttons reach OST. The change is about 20 lines and
only switches which bus the client connects to.

With the patched plugin, enable it in WirePlumber by copying
`ost-hfp-modem.conf` to `~/.config/wireplumber/wireplumber.conf.d/` and
restarting WirePlumber.

Stock PipeWire never asks for OST's modem. OST notices, logs that answer and
hang-up aren't offered, and shows nothing, as Teams shows nothing where the
platform lacks call control. The headset's mute still works on stock
PipeWire: the headset's microphone gain (AT+VGM) going to 0 and back mutes and
unmutes the call, and OST's own mute sets the gain to 0.
