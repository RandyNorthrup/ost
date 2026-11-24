#!/bin/sh
# Bluetooth headset call buttons for OST on stock PipeWire/WirePlumber.
#
# PipeWire's HFP audio gateway rings a headset for a modem's incoming call and
# gives its answer (ATA) and hang-up (AT+CHUP) to that modem's calls. It looks
# for the modem at ModemManager's name on the system bus. OST offers its calls
# there, as Teams reports its calls to Windows' VoIP call coordinator. This
# sets that up:
#   1. ~/.config/wireplumber/wireplumber.conf.d/ost-hfp-calls.conf: the
#      gateway looks for OST's modem (WirePlumber is restarted).
#   2. /etc/dbus-1/system.d/ost-hfp-calls.conf (sudo): your user may own
#      ModemManager's name on the system bus.
#   3. ModemManager mustn't hold that name. If it runs and has no modems, it's
#      stopped and disabled (asked first, or --yes); with a modem it's left
#      alone and the buttons stay unavailable.
#
#   sh install-hfp-calls.sh [--yes]     set up
#   sh install-hfp-calls.sh --uninstall undo all of it (ModemManager is
#                                       enabled again if this script disabled it)
#
# The headset's mute works without any of this. PipeWire with
# contrib/pipewire's patch is the other way (no system changes, a rebuilt
# PipeWire).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
user=$(id -un)
wp_conf="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d/ost-hfp-calls.conf"
policy=/etc/dbus-1/system.d/ost-hfp-calls.conf
state="${XDG_DATA_HOME:-$HOME/.local/share}/ost/hfp-calls-disabled-modemmanager"
yes=0
mode=install
for a in "$@"; do
  case "$a" in
    --yes|-y) yes=1 ;;
    --uninstall) mode=uninstall ;;
    *) echo "usage: $0 [--yes] [--uninstall]" >&2; exit 2 ;;
  esac
done

restart_wireplumber() {
  systemctl --user restart wireplumber 2>/dev/null || echo "Restart WirePlumber (or log out and in) to apply."
}

mm_active() {
  systemctl is-active --quiet ModemManager 2>/dev/null
}

if [ "$mode" = uninstall ]; then
  rm -f "$wp_conf"
  restart_wireplumber
  [ -e "$policy" ] && sudo rm -f "$policy"
  if [ -e "$state" ]; then
    sudo systemctl enable --now ModemManager
    rm -f "$state"
    echo "ModemManager enabled again."
  fi
  echo "Removed OST's headset call setup."
  exit 0
fi

case "$user" in
  *[!A-Za-z0-9._-]*) echo "unexpected user name: $user" >&2; exit 1 ;;
esac

install -Dm644 "$here/ost-hfp-calls.wireplumber.conf" "$wp_conf"
sed "s/@USER@/$user/g" "$here/ost-hfp-calls.dbus.conf" | sudo tee "$policy" > /dev/null
sudo chmod 644 "$policy"
echo "Installed $policy and $wp_conf."

if mm_active; then
  modems=$(mmcli -L 2>/dev/null | grep -c '/Modem/' || true)
  if [ "$modems" -gt 0 ]; then
    echo "ModemManager runs with a modem, so it keeps ModemManager's name and OST can't offer its calls to"
    echo "Bluetooth headsets (their mute still works). See contrib/pipewire for the other way."
  else
    answer=n
    if [ "$yes" = 1 ]; then
      answer=y
    elif [ -t 0 ]; then
      printf "ModemManager runs without a modem and holds the name OST needs. Stop and disable it? [y/N] "
      read -r answer || answer=n
    fi
    case "$answer" in
      y|Y|yes)
        sudo systemctl disable --now ModemManager
        mkdir -p "$(dirname "$state")"
        : > "$state"
        echo "ModemManager stopped and disabled (--uninstall enables it again)."
        ;;
      *)
        echo "ModemManager left running: headset answer and hang-up stay unavailable until it's stopped."
        ;;
    esac
  fi
fi

restart_wireplumber
echo "Done. OST offers its calls to Bluetooth headsets while it has the headset buttons (Settings > Devices)."
