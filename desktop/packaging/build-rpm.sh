#!/bin/sh
# Build OST's RPM packages (ost-desktop, teams-cli) on the Fedora or
# openSUSE release they are for, against its own Rust, Qt, FFmpeg,
# PipeWire, OpenSSL and webrtc-audio-processing:
#
#   sh desktop/packaging/build-rpm.sh [--deps|--deps-only] <version> [work dir]
#
# --deps (as root, e.g. in a container) first installs rpm-build and the
# spec's BuildRequires (dnf or zypper); --deps-only installs them and stops.
# The packages land in <work dir> (default target/rpm). CARGO_TARGET_DIR
# keeps the build between runs; JOBS caps the compile jobs.
set -eu
deps=0
case "${1:-}" in --deps) deps=1; shift ;; --deps-only) deps=2; shift ;; esac
V=${1:-0}
SRC=$(cd "$(dirname "$0")/../.." && pwd)
W=${2:-$SRC/target/rpm}
mkdir -p "$W"
W=$(cd "$W" && pwd)
JOBS=${JOBS:-$(nproc)}
SPEC="$SRC/desktop/packaging/rpm/ost-desktop.spec"
# RPM versions have no "-": a pre-release (0.2.1-rc1) becomes 0.2.1~rc1.
RV=$(printf %s "$V" | tr - "~")
. /etc/os-release
# Fedora's packages carry .fcNN; openSUSE's get .suse.tw or .suse.leapNN.N.
case "$ID" in
  opensuse-tumbleweed) dist=".suse.tw" ;;
  opensuse-leap) dist=".suse.leap$VERSION_ID" ;;
  *) dist="" ;;
esac

if [ "$deps" != 0 ]; then
  if command -v dnf >/dev/null; then
    dnf install -y -q rpm-build 'dnf-command(builddep)'
    dnf builddep -y -q "$SPEC"
  else
    # --force-resolution: busybox stand-ins (busybox-gawk…) make way for the real tools.
    zypper -n -q install --force-resolution rpm-build
    # zypper has no builddep: the spec's BuildRequires, as listed by rpmspec.
    rpmspec -q --buildrequires "$SPEC" | sed "s/ //g" | xargs zypper -n -q install --force-resolution
  fi
  [ "$deps" = 2 ] && exit 0
fi

mkdir -p "$W/SOURCES"
(cd "$SRC" && tar --exclude=./target --exclude=./.git --exclude=./.claude \
  --transform "s,^\.,ost-$RV," -czf "$W/SOURCES/ost-$RV.tar.gz" .)
when=${SOURCE_DATE_EPOCH:-$(git -C "$SRC" log -1 --format=%ct 2>/dev/null || date +%s)}
{
  sed "s/^Version:.*/Version:        $RV/" "$SPEC"
  printf '\n%%changelog\n* %s Randy Northrup <randy.northrup@gmail.com> - %s-1\n- OST %s: https://github.com/RandyNorthrup/ost/releases/tag/v%s\n' \
    "$(LC_ALL=C date -u -d "@$when" '+%a %b %d %Y')" "$RV" "$V" "$V"
} > "$W/ost-desktop.spec"
set -- --define "_topdir $W" --define "_smp_mflags -j$JOBS"
[ -n "$dist" ] && set -- "$@" --define "dist $dist"
rpmbuild -bb "$@" "$W/ost-desktop.spec"
rm -rf "$W/BUILD" "$W/BUILDROOT"
ls -la "$W"/RPMS/*/*-"$RV"-*.rpm
