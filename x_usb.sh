#!/usr/bin/env bash
# ===========================================================================
#  DK USB passthrough: Windows -> WSL2 (-> container) with usbipd-win
# ===========================================================================
#    ./x_usb.sh setup     once per machine: usbipd-win on Windows (admin
#                         prompt), USB/IP + udev rule in WSL (sudo)
#    ./x_usb.sh attach    hand every J-Link (DK) to WSL       [default]
#    ./x_usb.sh detach    give them back to Windows
#    ./x_usb.sh list      what Windows sees, and what WSL has
#
#  You rarely need attach by hand: ./4_flash.sh, ./5_debug.sh and
#  ./7_test.sh test-hardware attach before they start. Use it before opening
#  the VS Code dev container (which cannot reach usbipd itself), or after
#  replugging/power-cycling a DK, which drops the attachment.
#
#  While attached, the DK is invisible to Windows (nRF Connect for Desktop,
#  J-Link tools, COM ports) - detach to use it from Windows again.
# ===========================================================================
set -euo pipefail
FIREFLY_HOST_ONLY=1
source "$(dirname "$0")/variables.sh"

[ -z "${FIREFLY_CONTAINER:-}" ] || {
    c_err "Run this from a WSL terminal - usbipd.exe is not reachable from the container."
    exit 1
}

UDEV_RULE=/etc/udev/rules.d/99-firefly-usb.rules

do_setup() {
    if usbipd_bin >/dev/null; then
        c_ok "usbipd-win: $("$(usbipd_bin)" --version 2>/dev/null | tr -d '\r')"
    else
        c_info "Installing usbipd-win on Windows (approve the admin prompt)..."
        winget.exe install --exact --id dorssel.usbipd-win \
            --accept-package-agreements --accept-source-agreements || {
            c_err "!!! winget failed. Install usbipd-win by hand from"
            c_err "    https://github.com/dorssel/usbipd-win/releases and re-run."
            exit 1
        }
        usbipd_bin >/dev/null || {
            c_err "!!! Installed, but usbipd.exe is not at $USBIPD_EXE yet."
            c_err "    Open a new WSL terminal and re-run (or set USBIPD_EXE)."
            exit 1
        }
    fi

    # vhci_hcd is the WSL side of USB/IP. Loading it at boot also makes
    # /dev/bus/usb exist before anything is attached, which the dev
    # container needs to bind-mount it.
    c_info "Loading USB/IP (vhci_hcd) now and at every WSL boot..."
    echo vhci_hcd | sudo tee /etc/modules-load.d/firefly-usbip.conf >/dev/null
    sudo modprobe vhci_hcd

    # J-Link USB nodes and the DKs' CDC-ACM consoles default to root/dialout.
    # The container user matches your UID but not your groups, so open them up.
    c_info "Installing $UDEV_RULE..."
    sudo tee "$UDEV_RULE" >/dev/null <<RULES
# firefly (x_usb.sh): J-Link probes and their serial ports, usable without root
# from WSL and the firefly-dev container.
SUBSYSTEM=="usb", ATTR{idVendor}=="$JLINK_USB_VID", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="$JLINK_USB_VID", MODE="0666"
RULES
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --subsystem-match=tty

    c_ok ""
    c_ok "USB passthrough ready. Plug in a DK, then: ./x_usb.sh attach  (or just ./4_flash.sh)"
}

do_list() {
    local bin; bin="$(usbipd_bin)" || { c_err "!!! usbipd-win not installed - ./x_usb.sh setup"; exit 1; }
    c_info "Windows (usbipd list):"
    "$bin" list | tr -d '\r'
    c_info ""
    c_info "J-Links attached to WSL (use as PROBE_SERIAL):"
    attached_probe_serials | sed 's/^/  /'
    ls /dev/ttyACM* 2>/dev/null | sed 's/^/  serial: /' || true
}

do_detach() {
    local bin busid state; bin="$(usbipd_bin)" || { c_err "!!! usbipd-win not installed"; exit 1; }
    while read -r busid state; do
        [ "$state" = attached ] || continue
        c_info "Detaching bus $busid"
        "$bin" detach --busid "$busid"
    done < <(usbipd_probes)
    c_ok "J-Links are back on Windows."
}

case "${1:-attach}" in
    setup)  do_setup ;;
    attach) usb_attach_probes && do_list ;;
    detach) do_detach ;;
    list)   do_list ;;
    *)      c_err "usage: $0 [setup|attach|detach|list]"; exit 2 ;;
esac
