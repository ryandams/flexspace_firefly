#!/usr/bin/env bash
# ===========================================================================
#  4. Flash the board selected in firefly-app/prj.conf
# ===========================================================================
#  The DK's on-board J-Link is passed from Windows to WSL with usbipd-win and
#  used as a local USB probe (one-time machine setup: ./x_usb.sh setup).
#  Run from WSL, this attaches the probe itself before entering the
#  container; the first time for a given DK/USB port, Windows asks for admin
#  approval to share it.
#
#      ./4_flash.sh            the development build (./3_build.sh)
#      ./4_flash.sh release    the signed release build (./3_build.sh release)
#
#  Several J-Links attached: PROBE_SERIAL=<serial> ./4_flash.sh
#  (./x_usb.sh list shows them).
# ===========================================================================
set -euo pipefail
FIREFLY_USB=1
source "$(dirname "$0")/variables.sh"

case "${1:-}" in
    "")      build="" ;;
    release) build=" release"; BUILD_DIR="$RELEASE_BUILD_DIR" ;;
    *)       c_err "usage: $0 [release]"; exit 2 ;;
esac
[ -d "$BUILD_DIR" ] || { c_err "!!! No build - run ./3_build.sh$build first"; exit 1; }

select_probe || exit 1
args=(west flash --build-dir "$BUILD_DIR" -r "$FLASH_RUNNER" "${PROBE_ARGS[@]}")

cd "$WORKSPACE_DIR"
if ! ncs "${args[@]}"; then
    c_err ""
    c_err "!!! Flash failed. Check in order:"
    c_err "    1. DK powered, and the J-Link still attached? ./x_usb.sh list"
    c_err "       (a DK power-cycle or replug drops the attachment - re-run this)"
    c_err "    2. Another program using the probe? Only one J-Link client at a time."
    c_err "    3. Device protected? Recover it, then flash again:"
    c_err "       ./0_docker.sh shell, then: nrfutil device recover --serial-number ${PROBE_ARGS[1]}"
    exit 1
fi

c_ok ""
c_ok "Flashed. The DK's serial console is in WSL too while it is attached:"
c_ok "  $(serial_ports | tr '\n' ' ')"
c_ok "(./x_usb.sh detach hands the DK back to Windows.)"
