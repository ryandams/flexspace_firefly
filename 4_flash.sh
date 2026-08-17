#!/usr/bin/env bash
# ===========================================================================
#  4. Flash the current TARGET board from WSL2
# ===========================================================================
#  WSL2 has no native USB, so the debug probe is not visible here. Instead of
#  usbipd passthrough (fiddly, and with known J-Link issues), this connects to
#  a J-Link remote server running on Windows over TCP.
#
#  On Windows, once per session:
#      JLinkRemoteServer.exe
#
#  Then from here (flashes whatever TARGET was last built - see variables.sh):
#      ./4_flash.sh
#      TARGET=nrf93m1dk ./4_flash.sh
#
#  Override the host with:  JLINK_HOST=192.168.1.50 ./4_flash.sh
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"

[ -d "$BUILD_DIR" ] || { c_err "!!! No build - run ./3_build.sh first"; exit 1; }

host="$(windows_host_ip)"
if [ -z "$host" ]; then
    c_err "!!! Could not work out the Windows host IP."
    c_err "    Set it explicitly:  JLINK_HOST=<ip> ./4_flash.sh"
    exit 1
fi

c_info "J-Link remote server expected at $host"
[ -n "$PROBE_SERIAL" ] && c_warn "PROBE_SERIAL is set but ignored - the remote bridge reaches" \
    "whichever probe JLinkRemoteServer.exe has open on the Windows side, not by serial."
args=(west flash --build-dir "$BUILD_DIR" -r jlink --dev-id "$host")

cd "$WORKSPACE_DIR"
if ! ncs "${args[@]}"; then
    c_err ""
    c_err "!!! Flash failed. Check in order:"
    c_err "    1. JLinkExe installed locally in WSL2? ('required program JLinkExe"
    c_err "       not found' means it isn't - see ./0_prereqs.sh for how)"
    c_err "    2. JLinkRemoteServer.exe running on Windows?"
    c_err "    3. Its banner IP matches '$host' (printed above)? If not:"
    c_err "       JLINK_HOST=<that ip> ./4_flash.sh"
    c_err "    4. Windows firewall allowing it on the WSL virtual adapter?"
    c_err "    5. DK powered and enumerated on the Windows side?"
    c_err "    6. Device protected? Recover it with nrfutil on the host that owns the probe."
    exit 1
fi

c_ok ""
c_ok "Flashed. Serial console is on the Windows side - use a terminal there,"
c_ok "or attach the CDC device into WSL2 with usbipd if you prefer."
