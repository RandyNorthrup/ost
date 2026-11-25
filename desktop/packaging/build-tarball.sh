#!/bin/sh
# Pack the release tarball: the AppImage with the install scripts (menu
# entry, icon, metainfo, Bluetooth headset setup), LICENSE and INSTALL notes.
#
#   sh desktop/packaging/build-tarball.sh <version> <AppImage> [out dir]
#
# Writes <out dir>/ost-<version>-linux-x86_64.tar.gz (default: the
# AppImage's directory).
set -eu
V=$1
APP=$(readlink -f "$2")
SRC=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(readlink -f "${3:-$(dirname "$APP")}")
N="ost-$V-linux-x86_64"
P="$SRC/desktop/packaging"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/$N/packaging"
cp "$APP" "$T/$N/OST-$V-x86_64.AppImage"
chmod 755 "$T/$N/OST-$V-x86_64.AppImage"
cp "$SRC/LICENSE" "$T/$N/"
for f in install-user.sh install-hfp-calls.sh ost-hfp-calls.dbus.conf ost-hfp-calls.wireplumber.conf \
         io.github.RandyNorthrup.ost.desktop io.github.RandyNorthrup.ost.png io.github.RandyNorthrup.ost.metainfo.xml; do
  cp "$P/$f" "$T/$N/packaging/"
done
cat > "$T/$N/INSTALL.md" <<EOF
# OST $V

Run OST directly:

    ./OST-$V-x86_64.AppImage

Or add it to your app menu (~/.local/bin/ost-desktop, menu entry and icon):

    sh packaging/install-user.sh ./OST-$V-x86_64.AppImage
    ost-desktop

The terminal client is in the same file: \`./OST-$V-x86_64.AppImage teams-cli tui\`.

Bluetooth headset answer and hang-up buttons need a one-time PipeWire setup:
\`sh packaging/install-hfp-calls.sh\` (\`--uninstall\` undoes it).

Needs 64-bit x86 Linux with glibc 2.43 or newer, FUSE 3 (\`fuse3\`), PipeWire and a
Secret Service keyring. The release also has .deb and .rpm packages and a Flatpak
bundle. More: https://github.com/RandyNorthrup/ost/wiki/Installation
EOF
tar -C "$T" --owner=0 --group=0 -czf "$OUT/$N.tar.gz" "$N"
ls -la "$OUT/$N.tar.gz"
