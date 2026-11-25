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
# Needs qmake6 (QMAKE=…), curl, git, cmake, a C++ compiler, pkg-config,
# patchelf, nlohmann-json, CImg, libpng and libjpeg headers, and LayerShellQt
# (liblayershellqtinterface6) installed (build-deb.sh --deps-only plus the
# release workflow's list).
#
# The build tools, all pinned (bump them together, after checking the new
# versions' release notes):
#   - linuxdeploy and appimagetool: release files at exact versions, and the
#     AppImage runtime appimagetool embeds (it would otherwise download the
#     latest one), each checked against its SHA-256 before it runs;
#   - linuxdeploy-plugin-qt: built here from an exact commit (its only
#     versioned release predates the Wayland, networkinformation and Qt 6
#     AppRun changes OST's AppImage needs), with its submodules at the commits
#     that commit records, its build dependencies from the distribution, and
#     the library exclude list it compiles in from a pinned commit, checked
#     against its SHA-256.
# They are kept in <work dir>/tools; every run checks them again.
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

LINUXDEPLOY_URL=https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage
LINUXDEPLOY_SHA256=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
APPIMAGETOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_URL=https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
PLUGIN_QT_REPO=https://github.com/linuxdeploy/linuxdeploy-plugin-qt
PLUGIN_QT_COMMIT=9b9fca179e7312ae4a433ad6c3183d73c116180b
EXCLUDELIST_URL=https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/15a64c20dc23a0154622ba25829364323903b6b5/excludelist
EXCLUDELIST_SHA256=50db0f894f34b169c47a5cbc0c17dbab61e9edebca5bc8269a1e6ac1bf4bdad9

# fetch <url> <sha256> <file>: download once, check the hash on every run.
fetch() {
  if [ ! -f "$3" ]; then
    curl -fsSL --retry 3 -o "$3.part" "$1"
    mv "$3.part" "$3"
  fi
  if ! printf '%s  %s\n' "$2" "$3" | sha256sum -c --quiet -; then
    echo "error: $3 doesn't match its pinned SHA-256 ($1)" >&2
    rm -f "$3"
    exit 1
  fi
}

mkdir -p "$T"
fetch "$LINUXDEPLOY_URL" "$LINUXDEPLOY_SHA256" "$T/linuxdeploy-x86_64.AppImage"
fetch "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256" "$T/appimagetool-x86_64.AppImage"
fetch "$RUNTIME_URL" "$RUNTIME_SHA256" "$T/runtime-x86_64"
chmod +x "$T/linuxdeploy-x86_64.AppImage" "$T/appimagetool-x86_64.AppImage"

if [ "$(cat "$T/linuxdeploy-plugin-qt.commit" 2>/dev/null)" != "$PLUGIN_QT_COMMIT" ] || [ ! -x "$T/linuxdeploy-plugin-qt" ]; then
  P=$T/linuxdeploy-plugin-qt-src
  rm -rf "$P" "$T/linuxdeploy-plugin-qt" "$T/linuxdeploy-plugin-qt.commit"
  git init -q "$P"
  git -C "$P" fetch -q --depth 1 "$PLUGIN_QT_REPO" "$PLUGIN_QT_COMMIT"
  git -C "$P" checkout -q --detach FETCH_HEAD
  [ "$(git -C "$P" rev-parse HEAD)" = "$PLUGIN_QT_COMMIT" ] || { echo "error: linuxdeploy-plugin-qt isn't at $PLUGIN_QT_COMMIT" >&2; exit 1; }
  git -C "$P" submodule -q update --init --recursive
  # linuxdeploy's build downloads its library exclude list from a moving
  # branch: it reads the pinned, checked copy instead.
  fetch "$EXCLUDELIST_URL" "$EXCLUDELIST_SHA256" "$T/excludelist"
  G=$P/lib/linuxdeploy/src/core/generate-excludelist.sh
  sed -i "s|wget --quiet \"\$url\" -O -|cat '$T/excludelist'|" "$G"
  grep -q "cat '$T/excludelist'" "$G" || { echo "error: $G changed; update build-appimage.sh" >&2; exit 1; }
  # Its dependencies come from the system; nothing is fetched at build time.
  cmake -S "$P" -B "$P/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DFETCHCONTENT_FULLY_DISCONNECTED=ON >/dev/null
  cmake --build "$P/build" --target linuxdeploy-plugin-qt -j "$(nproc)" >/dev/null
  install -m755 "$P/build/bin/linuxdeploy-plugin-qt" "$T/linuxdeploy-plugin-qt"
  echo "$PLUGIN_QT_COMMIT" > "$T/linuxdeploy-plugin-qt.commit"
  rm -rf "$P"
fi
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

ARCH=x86_64 VERSION="$V" appimagetool-x86_64.AppImage --no-appstream --runtime-file "$T/runtime-x86_64" AppDir "$OUT"
ls -la "$OUT"
