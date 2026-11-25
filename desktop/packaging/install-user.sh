#!/bin/sh
# Install ost-desktop for the current user: binary, desktop entry, icon,
# AppStream metainfo.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
id=io.github.RandyNorthrup.ost
bin=${1:-"$here/../../target/release/ost-desktop"}
data=${XDG_DATA_HOME:-$HOME/.local/share}
install -Dm755 "$bin" "$HOME/.local/bin/ost-desktop"
install -Dm644 "$here/$id.desktop" "$data/applications/$id.desktop"
install -Dm644 "$here/$id.png" "$data/icons/hicolor/256x256/apps/$id.png"
install -Dm644 "$here/$id.metainfo.xml" "$data/metainfo/$id.metainfo.xml"
# Before 0.2.1 the entry and icon were named ost-desktop.
rm -f "$data/applications/ost-desktop.desktop" "$data/icons/hicolor/256x256/apps/ost-desktop.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$data/applications" || true
echo "Installed. Launch OST from your app launcher or run ost-desktop."
echo "Bluetooth headset answer and hang-up buttons: sh $here/install-hfp-calls.sh (uses sudo once)."
