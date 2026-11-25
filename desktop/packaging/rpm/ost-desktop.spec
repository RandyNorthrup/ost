# OST's RPM packages (ost-desktop, teams-cli) for Fedora and openSUSE,
# built against the distribution's Rust, Qt, FFmpeg, PipeWire, OpenSSL and
# webrtc-audio-processing by desktop/packaging/build-rpm.sh.

%global appid io.github.RandyNorthrup.ost
# Release builds carry no debug info.
%global debug_package %{nil}
# No GCC LTO: cxx-qt's C++ is linked by rustc (with lld), which can't read
# GCC's LTO objects.
%global _lto_cflags %{nil}

Name:           ost-desktop
Version:        0
Release:        1%{?dist}
Summary:        Native Linux desktop client for Microsoft Teams (unofficial)
License:        MIT
URL:            https://github.com/RandyNorthrup/ost/wiki
Source0:        ost-%{version}.tar.gz
ExclusiveArch:  x86_64

BuildRequires:  cargo >= 1.91
BuildRequires:  rust >= 1.91
BuildRequires:  clang
# cxx-qt links with lld (or mold); GNU ld.bfd drops Qt and FFmpeg libraries.
BuildRequires:  lld
BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  nasm
BuildRequires:  pkgconfig
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(Qt6QuickControls2)
BuildRequires:  cmake(Qt6Multimedia)
BuildRequires:  cmake(Qt6WebEngineQuick)
BuildRequires:  cmake(Qt6WebChannel)
BuildRequires:  cmake(Qt6Pdf)
BuildRequires:  cmake(Qt6PdfQuick)
BuildRequires:  cmake(Qt6Svg)
BuildRequires:  cmake(Qt6ShaderTools)
BuildRequires:  pkgconfig(libavcodec)
BuildRequires:  pkgconfig(libavfilter)
BuildRequires:  pkgconfig(libavformat)
BuildRequires:  pkgconfig(libavutil)
BuildRequires:  pkgconfig(libswscale)
BuildRequires:  pkgconfig(alsa)
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(opus)
BuildRequires:  pkgconfig(dbus-1)
BuildRequires:  pkgconfig(webrtc-audio-processing-1)
%if 0%{?suse_version}
BuildRequires:  qt6-shadertools
%else
BuildRequires:  qt6-qtshadertools
%endif

# The shared libraries are found automatically; Qt's QML modules and
# plugins that OST loads at run time are not.
%if 0%{?suse_version}
Requires:       qt6-declarative-imports
Requires:       qt6-multimedia-imports
Requires:       qt6-webengine-imports
Requires:       qt6-webchannel-imports
Requires:       qt6-pdf-imports
Requires:       qt6-wayland
Requires:       libQt6Svg6
Requires:       qt6-imageformats
Recommends:     layer-shell-qt6
%else
Requires:       qt6-qtdeclarative
Requires:       qt6-qtmultimedia
Requires:       qt6-qtwebengine
Requires:       qt6-qtwebchannel
Requires:       qt6-qtpdf
Requires:       qt6-qtwayland
Requires:       qt6-qtsvg
Requires:       qt6-qtimageformats
Recommends:     layer-shell-qt
%endif
Recommends:     pipewire
Recommends:     wireplumber
Recommends:     xdg-desktop-portal
Recommends:     (gnome-keyring or kwalletmanager5 or kwalletmanager or keepassxc)
Suggests:       teams-cli

%description
Native Linux desktop client for Microsoft Teams: chat, channels, calls and
meetings, calendar and files, built in Rust and Qt Quick. Unofficial, not
affiliated with Microsoft.

OST looks and works like the Teams desktop app; only the name and the logo
differ. Sign in with your own Microsoft work or school account.

Bluetooth headset answer and hang-up buttons need a one-time PipeWire setup:
sh %{_datadir}/ost-desktop/install-hfp-calls.sh

%package -n teams-cli
Summary:        Terminal client for Microsoft Teams (unofficial)
Recommends:     pipewire

%description -n teams-cli
teams-cli is OST's terminal client for Microsoft Teams: chats, channels and
calls in a text interface, and command-line tools. Unofficial, not affiliated
with Microsoft.

%prep
%autosetup -n ost-%{version}

%build
export QMAKE=$(command -v qmake6 || echo %{_libdir}/qt6/bin/qmake)
cargo build --release --locked %{?_smp_mflags} -p ost-desktop
cargo build --release --locked %{?_smp_mflags} --bin teams-cli --features audio

%install
T=${CARGO_TARGET_DIR:-target}/release
P=desktop/packaging
install -Dm755 $T/ost-desktop %{buildroot}%{_bindir}/ost-desktop
install -Dm755 $T/teams-cli %{buildroot}%{_bindir}/teams-cli
install -Dm644 $P/%{appid}.desktop %{buildroot}%{_datadir}/applications/%{appid}.desktop
install -Dm644 $P/%{appid}.png %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/%{appid}.png
install -Dm644 desktop/assets/logo.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/%{appid}.svg
install -Dm644 $P/%{appid}.metainfo.xml %{buildroot}%{_datadir}/metainfo/%{appid}.metainfo.xml
install -Dm755 $P/install-hfp-calls.sh %{buildroot}%{_datadir}/ost-desktop/install-hfp-calls.sh
install -Dm644 $P/ost-hfp-calls.dbus.conf %{buildroot}%{_datadir}/ost-desktop/ost-hfp-calls.dbus.conf
install -Dm644 $P/ost-hfp-calls.wireplumber.conf %{buildroot}%{_datadir}/ost-desktop/ost-hfp-calls.wireplumber.conf

%files
%license LICENSE
%doc README.md desktop/THIRD-PARTY-NOTICES.md
%{_bindir}/ost-desktop
%{_datadir}/applications/%{appid}.desktop
%{_datadir}/icons/hicolor/256x256/apps/%{appid}.png
%{_datadir}/icons/hicolor/scalable/apps/%{appid}.svg
%{_datadir}/metainfo/%{appid}.metainfo.xml
%{_datadir}/ost-desktop/

%files -n teams-cli
%license LICENSE
%{_bindir}/teams-cli
