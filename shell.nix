{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    ccache
    pkg-config
    flex
    bison
    gnumake
    gettext
    pkgsCross.mingw32.buildPackages.gcc
    pkgsCross.mingwW64.buildPackages.gcc
    libx11
    libxext
    libxrandr
    libxcursor
    libxi
    libxrender
    libxfixes
    libxinerama
    libxcb
    libxxf86vm
    libxcomposite
    freetype
    fontconfig
    mesa
    libGL
    libGLU
    vulkan-loader
    vulkan-headers
    wayland
    wayland-protocols
    libxkbcommon
    ocl-icd
    libpcap
    pcsclite
    dbus
    sane-backends
    libusb1
    libgphoto2
    systemd
    v4l-utils
    alsa-lib
    libpulseaudio
    SDL2
    ffmpeg
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    cups
    krb5
    gnutls
    samba

    # valgrind-full.sh runtime dependencies
    mesa-demos
    git
    # gnused
    wget
    cabextract
    winetricks
    time

    # Tools
    valgrind
    cppcheck

  ];
  shellHook = ''
    export WINESRC=~/Faks/vs/wine/2024_Analysis_wine/wine
    export WINEDLLOVERRIDES="mscoree,mshtml="

    export CCACHE_DIR="''${CCACHE_DIR:-$HOME/.cache/ccache-wine}"
    export CCACHE_MAXSIZE="40G"
    export CCACHE_COMPRESS="1"
    export CCACHE_COMPILERCHECK="content"
    export CCACHE_SLOPPINESS="time_macros,locale"
    export CCACHE_BASEDIR="$HOME/Faks/vs/wine"
  '';
}
