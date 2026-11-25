#!/bin/sh
# Bluetooth headset call buttons for OST on stock PipeWire/WirePlumber.
# Optional: the headset's mute works without any of this.
#
# PipeWire's HFP audio gateway rings a headset for a modem's incoming call and
# gives its answer (ATA) and hang-up (AT+CHUP) to that modem's calls. It looks
# for the modem at ModemManager's name on the system bus. OST offers its calls
# there, as Teams reports its calls to Windows' VoIP call coordinator. Setting
# that up takes these changes, which the script lists and asks about before it
# makes any of them:
#   1. ~/.config/wireplumber/wireplumber.conf.d/ost-hfp-calls.conf (your
#      user): the gateway looks for OST's modem, never a real one's.
#   2. /etc/dbus-1/system.d/ost-hfp-calls.conf (sudo): your user may own
#      ModemManager's name (org.freedesktop.ModemManager1) on the system bus;
#      nobody else gains anything.
#   3. WirePlumber is restarted (audio pauses for a moment).
# And only if you agree to it separately: ModemManager mustn't hold that name.
# If it runs without any modem, the script asks whether to stop and disable it
# (mobile broadband modems aren't detected while it's off). With a modem it's
# never touched and the buttons stay unavailable. Without your answer
# (--disable-modemmanager, or "y" at its own question) it's left alone.
#
#   sh install-hfp-calls.sh             list the changes, ask, make them
#   sh install-hfp-calls.sh --dry-run   only list them
#   sh install-hfp-calls.sh --yes       make the file changes without asking
#                                       (ModemManager is still left alone)
#   sh install-hfp-calls.sh --disable-modemmanager
#                                       also agree to stopping and disabling
#                                       a modem-less ModemManager
#   sh install-hfp-calls.sh --uninstall put everything back as it was: files
#                                       this replaced are restored, the ones
#                                       it added removed, and ModemManager
#                                       enabled and started again if it was
#
# What it changed is kept in ~/.local/share/ost/hfp-calls/ for --uninstall.
# PipeWire with contrib/pipewire's patch is the other way (no system changes,
# a rebuilt PipeWire).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
user=$(id -un)
wp_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
wp_conf="$wp_dir/ost-hfp-calls.conf"
policy=/etc/dbus-1/system.d/ost-hfp-calls.conf
state="${XDG_DATA_HOME:-$HOME/.local/share}/ost/hfp-calls"
# The state file of this script's earlier versions (ModemManager disabled).
legacy_state="${XDG_DATA_HOME:-$HOME/.local/share}/ost/hfp-calls-disabled-modemmanager"
# Both installed files carry this in their header comment.
marker="OST: Bluetooth headset call buttons on stock PipeWire"
yes=0
dry=0
mm_consent=0
mode=install
for a in "$@"; do
  case "$a" in
    --yes|-y) yes=1 ;;
    --dry-run|-n) dry=1 ;;
    --disable-modemmanager) mm_consent=1 ;;
    --uninstall) mode=uninstall ;;
    *) echo "usage: $0 [--dry-run] [--yes] [--disable-modemmanager] | --uninstall [--dry-run]" >&2; exit 2 ;;
  esac
done

case "$user" in
  *[!A-Za-z0-9._-]*) echo "unexpected user name: $user" >&2; exit 1 ;;
esac

restart_wireplumber() {
  systemctl --user restart wireplumber 2>/dev/null || echo "Restart WirePlumber (or log out and in) to apply."
}

mm_active() {
  systemctl is-active --quiet ModemManager 2>/dev/null
}

# ours <file>: the file is one this script installed.
ours() {
  grep -qF "$marker" "$1" 2>/dev/null
}

# ask <question>: yes only for an answer of y/yes at a terminal.
ask() {
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  read -r reply || return 1
  case "$reply" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

if [ "$mode" = uninstall ]; then
  echo "Undoing OST's headset call setup:"
  if [ -f "$state/wireplumber.conf.orig" ]; then
    echo "  - restore your earlier $wp_conf"
  elif ours "$wp_conf"; then
    echo "  - remove $wp_conf"
  fi
  if [ -f "$state/created-dirs" ]; then
    echo "  - remove the folders it created, if they're empty: $(tr '\n' ' ' < "$state/created-dirs")"
  fi
  if [ -f "$state/dbus-policy.orig" ]; then
    echo "  - restore the earlier $policy (sudo)"
  elif ours "$policy"; then
    echo "  - remove $policy (sudo)"
  fi
  mm_enable=0; mm_start=0
  if [ -f "$state/modemmanager" ]; then
    # shellcheck disable=SC1091
    . "$state/modemmanager"
    [ "${was_enabled:-}" = enabled ] && mm_enable=1
    [ "${was_active:-}" = active ] && mm_start=1
  elif [ -e "$legacy_state" ]; then
    mm_enable=1; mm_start=1
  fi
  [ "$mm_enable" = 1 ] && echo "  - enable ModemManager again (sudo)"
  [ "$mm_start" = 1 ] && echo "  - start ModemManager again (sudo)"
  echo "  - restart WirePlumber"
  [ "$dry" = 1 ] && exit 0

  if [ -f "$state/wireplumber.conf.orig" ]; then
    cp -p "$state/wireplumber.conf.orig" "$wp_conf"
  elif ours "$wp_conf"; then
    rm -f "$wp_conf"
  fi
  if [ -f "$state/created-dirs" ]; then
    # Deepest first; a folder that has anything else in it stays.
    sort -r "$state/created-dirs" | while IFS= read -r d; do rmdir "$d" 2>/dev/null || true; done
  fi
  if [ -f "$state/dbus-policy.orig" ]; then
    sudo install -m644 -o root -g root "$state/dbus-policy.orig" "$policy"
  elif ours "$policy"; then
    sudo rm -f "$policy"
  fi
  [ "$mm_enable" = 1 ] && sudo systemctl enable ModemManager
  [ "$mm_start" = 1 ] && sudo systemctl start ModemManager
  restart_wireplumber
  rm -rf "$state"
  rm -f "$legacy_state"
  echo "Removed OST's headset call setup; everything it changed is back as it was."
  exit 0
fi

# What the two files will hold.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$here/ost-hfp-calls.wireplumber.conf" "$tmp/wireplumber.conf"
sed "s/@USER@/$user/g" "$here/ost-hfp-calls.dbus.conf" > "$tmp/dbus-policy.conf"

# describe <file> <new>: what writing <new> to <file> does.
describe() {
  if [ ! -e "$1" ]; then echo "create"
  elif cmp -s "$1" "$2"; then echo "keep (already set up)"
  elif ours "$1"; then echo "update OST's earlier version of"
  else echo "replace (your current file is kept for --uninstall)"
  fi
}

echo "OST's headset call setup makes these changes:"
echo "  1. $(describe "$wp_conf" "$tmp/wireplumber.conf") $wp_conf"
echo "     PipeWire's HFP gateway hands a headset's answer and hang-up to OST's calls."
echo "  2. $(describe "$policy" "$tmp/dbus-policy.conf") $policy (sudo)"
echo "     User $user may own org.freedesktop.ModemManager1 on the system bus, where OST"
echo "     offers its calls to PipeWire. Nobody else gains anything."
echo "  3. Restart WirePlumber: audio pauses for a moment."
mm_question=0
if mm_active; then
  modems=$(mmcli -L 2>/dev/null | grep -c '/Modem/' || true)
  if [ "$modems" -gt 0 ]; then
    echo "ModemManager runs with a modem, so it isn't touched: it keeps its name and OST can't"
    echo "offer its calls to Bluetooth headsets (their mute still works). See contrib/pipewire"
    echo "for the other way."
  else
    mm_question=1
    echo "ModemManager runs without a modem and holds the name OST needs. Stopping and"
    echo "disabling it is asked separately next (it is left alone unless you agree)."
  fi
fi
echo "--uninstall undoes all of it."
[ "$dry" = 1 ] && exit 0

if [ "$yes" != 1 ] && ! ask "Make changes 1-3?"; then
  echo "Nothing changed."
  exit 1
fi

mkdir -p "$state"
# Folders this creates, so --uninstall removes them again.
d=$wp_dir; new_dirs=""
while [ ! -d "$d" ]; do new_dirs="$d
$new_dirs"; d=$(dirname "$d"); done
if [ -n "$new_dirs" ]; then
  printf '%s' "$new_dirs" >> "$state/created-dirs"
fi
mkdir -p "$wp_dir"
if [ -e "$wp_conf" ] && ! ours "$wp_conf" && [ ! -e "$state/wireplumber.conf.orig" ]; then
  cp -p "$wp_conf" "$state/wireplumber.conf.orig"
fi
install -m644 "$tmp/wireplumber.conf" "$wp_conf"
if [ -e "$policy" ] && ! ours "$policy" && [ ! -e "$state/dbus-policy.orig" ]; then
  cp -p "$policy" "$state/dbus-policy.orig"
fi
sudo install -m644 -o root -g root "$tmp/dbus-policy.conf" "$policy"
echo "Installed $wp_conf and $policy."

if [ "$mm_question" = 1 ]; then
  echo
  echo "ModemManager detects mobile broadband (WWAN) modems; this computer has none right now."
  echo "Stopping and disabling it lets OST take its name, so headset answer and hang-up work."
  echo "A modem plugged in later isn't detected until it's enabled again (--uninstall does that)."
  if [ "$mm_consent" = 1 ] || ask "Stop and disable ModemManager?"; then
    if [ ! -f "$state/modemmanager" ]; then
      printf 'was_enabled=%s\nwas_active=%s\n' \
        "$(systemctl is-enabled ModemManager 2>/dev/null || true)" \
        "$(systemctl is-active ModemManager 2>/dev/null || true)" > "$state/modemmanager"
    fi
    sudo systemctl disable --now ModemManager
    echo "ModemManager stopped and disabled (--uninstall enables and starts it again)."
  else
    echo "ModemManager left as it is: headset answer and hang-up stay unavailable while it runs."
  fi
fi

restart_wireplumber
echo "Done. OST offers its calls to Bluetooth headsets while it has the headset buttons (Settings > Devices)."
