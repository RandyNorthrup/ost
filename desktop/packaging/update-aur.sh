#!/bin/sh
# Update OST's AUR packages (ost, ost-bin) to a released version and push
# them. Run as root in an archlinux container once the release has its
# AppImage (the release workflow's aur job):
#
#   AUR_SSH_KEY=<private key> sh desktop/packaging/update-aur.sh <version>
#
# For each desktop/packaging/aur/<pkg>/PKGBUILD: pkgver=<version>, pkgrel=1,
# fresh sums (updpkgsums) and .SRCINFO, pushed to aur.archlinux.org/<pkg>.git
# (the first push creates the package).
set -eu
V=$1
SRC=$(cd "$(dirname "$0")/../.." && pwd)
: "${AUR_SSH_KEY:?the AUR push key}"

pacman -Syu --noconfirm --needed base-devel pacman-contrib git openssh >/dev/null
id builder >/dev/null 2>&1 || useradd -m builder
H=/home/builder
install -d -m 700 -o builder "$H/.ssh"
printf '%s\n' "$AUR_SSH_KEY" > "$H/.ssh/aur"
chmod 600 "$H/.ssh/aur"
ssh-keyscan -t ed25519 aur.archlinux.org > "$H/.ssh/known_hosts" 2>/dev/null
cat > "$H/.ssh/config" <<'EOF'
Host aur.archlinux.org
  User aur
  IdentityFile ~/.ssh/aur
  IdentitiesOnly yes
EOF
chown -R builder "$H/.ssh"

for dir in "$SRC"/desktop/packaging/aur/*/; do
  pkg=$(basename "$dir")
  W="$H/aur-$pkg"
  rm -rf "$W"
  su builder -c "git clone -q ssh://aur@aur.archlinux.org/$pkg.git '$W'"
  # The AUR repo holds only the PKGBUILD, .SRCINFO and the files they name.
  find "$dir" -maxdepth 1 -type f -exec cp {} "$W/" \;
  chown -R builder "$W"
  su builder -c "cd '$W' && sed -i 's/^pkgver=.*/pkgver=$V/; s/^pkgrel=.*/pkgrel=1/' PKGBUILD && updpkgsums && makepkg --printsrcinfo > .SRCINFO"
  if su builder -c "cd '$W' && git add -A && git diff --cached --quiet"; then
    echo "$pkg: already at $V"
    continue
  fi
  su builder -c "cd '$W' && git -c user.name='Randy Northrup' -c user.email='randy.northrup@gmail.com' commit -q -m 'Update to $V' && git push -q origin HEAD:master"
  echo "$pkg $V pushed"
done
