#!/bin/sh
# Build OST's .deb packages (ost-desktop, teams-cli) on the Debian or Ubuntu
# release they are for, against its own Qt, FFmpeg, PipeWire, OpenSSL and
# webrtc-audio-processing:
#
#   sh desktop/packaging/build-deb.sh [--deps|--deps-only] <version> [work dir]
#
# --deps (as root, e.g. in a container) first installs the build
# dependencies from debian/control with apt (the distribution's Rust too);
# --deps-only installs them and stops.
# The packages are versioned <version>-1~<distro> (e.g. 0.2.1-1~ubuntu26.04)
# and land in <work dir> (default target/deb).
# CARGO_TARGET_DIR keeps the build between runs; JOBS caps the compile jobs.
set -eu
deps=0
case "${1:-}" in --deps) deps=1; shift ;; --deps-only) deps=2; shift ;; esac
V=${1:-0}
SRC=$(cd "$(dirname "$0")/../.." && pwd)
W=${2:-$SRC/target/deb}
mkdir -p "$W"
W=$(cd "$W" && pwd)
JOBS=${JOBS:-$(nproc)}
. /etc/os-release
DIST="$ID${VERSION_ID:-.${VERSION_CODENAME:-sid}}"
# A pre-release (0.2.1-rc1) sorts before its release: 0.2.1~rc1.
UV=$(printf %s "$V" | tr - "~")
DV="$UV-1~$DIST"

if [ "$deps" != 0 ]; then
  export DEBIAN_FRONTEND=noninteractive
  # A mirror in the middle of an update can list a package it no longer
  # has (404); retry with a fresh index before giving up.
  apt_retry() {
    for try in 1 2 3; do
      apt-get -o Acquire::Retries=3 update -q && apt-get -o Acquire::Retries=3 "$@" && return 0
      echo "apt-get $1 failed (try $try of 3); retrying with a fresh index" >&2
      sleep $((try * 20))
    done
    return 1
  }
  apt_retry install -y -q --no-install-recommends build-essential ca-certificates dpkg-dev debhelper file git
  # Build-Depends, one line, without the debhelper-compat entry.
  bd=$(sed -n '/^Build-Depends:/,/^[A-Z][A-Za-z-]*:/p' "$SRC/desktop/packaging/debian/control" \
    | sed '$d; s/^Build-Depends://' | tr -d '\n' | sed 's/debhelper-compat (= [0-9]*),//; s/,[[:space:]]*$//')
  apt_retry satisfy -y -q --no-install-recommends "$bd"
  [ "$deps" = 2 ] && exit 0
fi

# A copy of the source with debian/ at its top.
B="$W/ost-$UV"
rm -rf "$B"
mkdir -p "$B"
(cd "$SRC" && tar --exclude=./target --exclude=./.git --exclude=./.claude -cf - .) | tar -xf - -C "$B"
cp -r "$SRC/desktop/packaging/debian" "$B/debian"
when=${SOURCE_DATE_EPOCH:-$(git -C "$SRC" log -1 --format=%ct 2>/dev/null || date +%s)}
cat > "$B/debian/changelog" <<EOF
ost ($DV) unstable; urgency=medium

  * OST $V: https://github.com/RandyNorthrup/ost/releases/tag/v$V

 -- Randy Northrup <randy.northrup@gmail.com>  $(date -R -u -d "@$when")
EOF

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$B/target}"
cd "$B"
DEB_BUILD_OPTIONS="parallel=$JOBS ${DEB_BUILD_OPTIONS:-}" dpkg-buildpackage -b -us -uc
rm -rf "$B"
ls -la "$W"/*_"$DV"_*.deb
