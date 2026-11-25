#!/bin/sh
# Build OST's AppImage from a release build (cargo build --release -p
# ost-desktop; cargo build --release --bin teams-cli --features audio).
#
#   sh desktop/packaging/build-appimage.sh <version> [work dir]
#
# The AppImage runs on systems with the build machine's glibc or newer, so
# build it on the oldest system it should support (OST's releases: Ubuntu
# 26.04). It bundles Qt (QML modules, platform and Wayland plugins,
# multimedia, QtWebEngine), FFmpeg and webrtc-audio-processing; the system
# provides glibc, the C++ runtime, the GPU stack, PipeWire/ALSA/PulseAudio
# clients, D-Bus, systemd, the Wayland client libraries and OpenSSL.
#
# Needs qmake6 (QMAKE=…), curl, and LayerShellQt (liblayershellqtinterface6)
# installed. linuxdeploy, its Qt plugin and appimagetool are downloaded into
# <work dir>/tools on first use.
set -eu
V=$1
SRC=$(cd "$(dirname "$0")/../.." && pwd)
W=${2:-$SRC/target/appimage}
T=$W/tools
QMAKE=${QMAKE:-$(command -v qmake6 || echo /usr/lib/qt6/bin/qmake6)}
export QMAKE
LIB=$("$QMAKE" -query QT_INSTALL_LIBS)
QTP=$("$QMAKE" -query QT_INSTALL_PLUGINS)
OUT="$W/OST-$V-x86_64.AppImage"

mkdir -p "$T"
for u in https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
         https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage \
         https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage; do
  f="$T/$(basename "$u")"
  [ -x "$f" ] || { curl -fsSL -o "$f" "$u"; chmod +x "$f"; }
done
export PATH="$T:$PATH"

rm -rf "$W/AppDir" "$OUT"
cd "$W"
export APPIMAGE_EXTRACT_AND_RUN=1
export QML_SOURCES_PATHS="$SRC/desktop/qml"
export EXTRA_PLATFORM_PLUGINS="libqwayland.so;libqxcb.so"
export EXTRA_QT_MODULES="waylandclient;svg;multimedia;webenginequick;webchannel;pdf;pdfquick;network;dbus;positioning"
export EXTRA_QT_PLUGINS="wayland-shell-integration;wayland-decoration-client;xcbglintegrations;multimedia;tls;imageformats;iconengines;platforminputcontexts;networkinformation"

# Left to the system: the C++ runtime (a newer distribution's Mesa needs its
# own), PipeWire, ALSA and PulseAudio clients (their plugins and sockets are
# the system's), D-Bus, systemd, the Wayland client libraries (they pair
# with the system's EGL), OpenSSL (its certificate paths are the system's)
# and the GPU stack.
EXCLUDES="libstdc++.so* libgcc_s.so* libpipewire-0.3.so* libasound.so* libpulse*.so* libdbus-1.so* libsystemd.so* libwayland-*.so* libssl.so* libcrypto.so* libGL*.so* libEGL*.so* libgbm.so* libdrm.so* libvulkan.so*"
set --
for e in $EXCLUDES; do set -- "$@" --exclude-library "$e"; done

linuxdeploy-x86_64.AppImage --appdir AppDir "$@" \
  -e "$SRC/target/release/ost-desktop" \
  -e "$SRC/target/release/teams-cli" \
  -d "$SRC/desktop/packaging/io.github.RandyNorthrup.ost.desktop" \
  -i "$SRC/desktop/packaging/io.github.RandyNorthrup.ost.png" \
  -l "$LIB/libLayerShellQtInterface.so.6" \
  --plugin qt

# EGL on Wayland, which the Qt plugin doesn't pick, and LayerShellQt's
# shell (Teams-style banners on Wayland).
mkdir -p AppDir/usr/plugins/wayland-graphics-integration-client AppDir/usr/plugins/wayland-shell-integration
cp "$QTP/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so" AppDir/usr/plugins/wayland-graphics-integration-client/
cp "$QTP/wayland-shell-integration/liblayer-shell.so" AppDir/usr/plugins/wayland-shell-integration/
# Their own dependencies come from the bundle too (linuxdeploy sets their
# RUNPATH).
linuxdeploy-x86_64.AppImage --appdir AppDir "$@" \
  --deploy-deps-only AppDir/usr/plugins/wayland-graphics-integration-client \
  --deploy-deps-only AppDir/usr/plugins/wayland-shell-integration

# Qt Design Studio's metadata for the Controls styles isn't used at run time.
rm -rf AppDir/usr/qml/QtQuick/Controls/designer

# Whatever a plugin's own deployment brought in from the excluded set goes.
for e in $EXCLUDES; do rm -f AppDir/usr/lib/$e; done

install -Dm644 "$SRC/desktop/packaging/io.github.RandyNorthrup.ost.metainfo.xml" \
  AppDir/usr/share/metainfo/io.github.RandyNorthrup.ost.metainfo.xml

# AppRun: OST, or teams-cli ("<AppImage> teams-cli …", or the AppImage
# linked as teams-cli).
rm -f AppDir/AppRun
cat > AppDir/AppRun <<'EOF'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
if [ "${1:-}" = "teams-cli" ]; then shift; exec "$HERE/usr/bin/teams-cli" "$@"; fi
case "$(basename "${ARGV0:-ost-desktop}")" in teams-cli*) exec "$HERE/usr/bin/teams-cli" "$@" ;; esac
exec "$HERE/usr/bin/ost-desktop" "$@"
EOF
chmod 755 AppDir/AppRun

ARCH=x86_64 VERSION="$V" appimagetool-x86_64.AppImage --no-appstream AppDir "$OUT"
ls -la "$OUT"
