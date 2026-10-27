#!/usr/bin/env bash
# ===========================================================================
#  Serial log viewer in a WSL browser
# ===========================================================================
#    ./x_serial.sh install    once: Google Chrome
#    ./x_serial.sh            attach the DK, open the viewer as an app window
#
#  The viewer (SERIAL_VIEWER_HTML, default log_viewer.html in this repo) uses
#  the browser's Web Serial API, which only sees the ports of the OS the
#  browser runs on. Once usbipd hands the DK to WSL its COM ports are gone
#  from Windows, so the viewer has to run in a Linux browser here - WSLg
#  shows its window on the Windows desktop. It sees the DK's /dev/ttyACM*
#  (opened up by ./x_usb.sh setup's udev rule) and can stay connected while
#  ./4_flash.sh flashes over the J-Link, catching the boot log.
#
#  Google's Chrome .deb, because Ubuntu's Chromium is a snap, whose sandbox
#  blocks serial ports.
# ===========================================================================
set -euo pipefail
FIREFLY_HOST_ONLY=1
source "$(dirname "$0")/variables.sh"

[ -z "${FIREFLY_CONTAINER:-}" ] || {
    c_err "Run this from a WSL terminal - the browser runs in WSL, not the container."
    exit 1
}

SERIAL_VIEWER_HTML="${SERIAL_VIEWER_HTML:-$FIREFLY_ROOT/log_viewer.html}"

install_chrome() {
    local deb
    deb="$(mktemp --suffix=.deb)"
    c_info "Downloading Google Chrome..."
    curl -fsSL -o "$deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    # The package also adds Google's apt repo, so it updates with apt upgrade.
    sudo apt-get install -y "$deb"
    rm -f "$deb"
    c_ok "Installed $(google-chrome --version)"
}

launch() {
    local bin
    bin="$(command -v google-chrome || true)"
    [ -n "$bin" ] || {
        c_err "!!! Google Chrome is not installed here - run: ./x_serial.sh install"
        exit 1
    }
    [ -f "$SERIAL_VIEWER_HTML" ] || {
        c_err "!!! Viewer not found: $SERIAL_VIEWER_HTML"
        c_err "    Point SERIAL_VIEWER_HTML at it, e.g. SERIAL_VIEWER_HTML=/mnt/c/.../viewer.html $0"
        exit 1
    }

    # The DK's serial ports only exist in WSL while it is attached.
    usb_attach_probes || exit 1
    local ports; ports="$(ls /dev/ttyACM* 2>/dev/null | tr '\n' ' ')"
    [ -n "$ports" ] || c_warn "J-Link attached, but no /dev/ttyACM* serial port appeared."

    c_info "Opening $SERIAL_VIEWER_HTML"
    c_info "  DK serial ports: ${ports:-none}  (pick one in the browser's port dialog)"
    # --app: a bare window without tabs or address bar, like the Windows shortcut.
    setsid "$bin" --app="file://$SERIAL_VIEWER_HTML" >/dev/null 2>&1 < /dev/null &
}

case "${1:-launch}" in
    install) install_chrome ;;
    launch)  launch ;;
    *) c_err "usage: $0 [launch|install]"; exit 2 ;;
esac
