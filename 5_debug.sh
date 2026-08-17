#!/usr/bin/env bash
# ===========================================================================
#  5. Single-step debug the current TARGET board from WSL2
# ===========================================================================
#  Same J-Link-over-TCP bridge as ./4_flash.sh (see that file for the
#  Windows-side setup). `west debug` launches JLinkGDBServer locally in
#  WSL2 - pointed at the remote probe via --dev-id <ip> - then attaches
#  arm-zephyr-eabi-gdb to it, halts, resets, and drops you into an
#  interactive GDB prompt. The J-Link device string (e.g. nRF54LM20A_M33 vs
#  nRF54L15_M33) comes from the board's own board.cmake, baked into the
#  build at ./3_build.sh time - this script needs no per-board changes.
#
#      ./5_debug.sh               plain GDB prompt
#      TARGET=nrf93m1dk ./5_debug.sh    debug whatever was last built for it
#      ./5_debug.sh --tui         split source/register view while stepping
#
#  Once at the (gdb) prompt:
#      break main            set a breakpoint (also: break file.c:42)
#      c                     continue
#      n / s                 step over / step into
#      p some_var            print a value
#      Ctrl-C                interrupt a running target
#      quit                  exit (also kills the JLinkGDBServer - -singlerun)
#
#  Override the host with:  JLINK_HOST=192.168.1.50 ./5_debug.sh
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"

[ -d "$BUILD_DIR" ] || { c_err "!!! No build - run ./3_build.sh first"; exit 1; }

host="$(windows_host_ip)"
if [ -z "$host" ]; then
    c_err "!!! Could not work out the Windows host IP."
    c_err "    Set it explicitly:  JLINK_HOST=<ip> ./5_debug.sh"
    exit 1
fi

c_info "J-Link remote server expected at $host"
[ -n "$PROBE_SERIAL" ] && c_warn "PROBE_SERIAL is set but ignored - the remote bridge reaches" \
    "whichever probe JLinkRemoteServer.exe has open on the Windows side, not by serial."
args=(west debug --build-dir "$BUILD_DIR" -r jlink --dev-id "$host")
args+=("$@")

cd "$WORKSPACE_DIR"
if ! ncs "${args[@]}"; then
    c_err ""
    c_err "!!! Debug session failed. Check in order (same as ./4_flash.sh):"
    c_err "    1. JLinkExe installed locally in WSL2? See ./0_prereqs.sh"
    c_err "    2. JLinkRemoteServer.exe running on Windows?"
    c_err "    3. Its banner IP matches '$host' (printed above)? If not:"
    c_err "       JLINK_HOST=<that ip> ./5_debug.sh"
    c_err "    4. Windows firewall allowing it on the WSL virtual adapter?"
    c_err "    5. DK powered and enumerated on the Windows side?"
    c_err "    6. Device protected? Recover it with nrfutil on the host that owns the probe."
    exit 1
fi
