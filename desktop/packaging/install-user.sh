#!/bin/sh
# Install ost-desktop for the current user: binary, desktop entry, icon.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:-"$here/../../target/release/ost-desktop"}
install -Dm755 "$bin" "$HOME/.local/bin/ost-desktop"
install -Dm644 "$here/ost-desktop.desktop" "$HOME/.local/share/applications/ost-desktop.desktop"
install -Dm644 "$here/ost-desktop.png" "$HOME/.local/share/icons/hicolor/256x256/apps/ost-desktop.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" || true
echo "Installed. Launch OST from your app launcher or run ost-desktop."
