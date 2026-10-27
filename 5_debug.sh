#!/usr/bin/env bash
# ===========================================================================
#  5. Single-step debug the board selected in firefly-app/prj.conf
# ===========================================================================
#  Same USB probe as ./4_flash.sh (usbipd-win - see there). `west debug`
#  launches JLinkGDBServer on the attached J-Link, then attaches
#  arm-zephyr-eabi-gdb to it, halts, resets, and drops you into an
#  interactive GDB prompt. The J-Link device string (e.g. nRF54LM20A_M33 vs
#  nRF54L15_M33) comes from the board's own board.cmake, baked into the
#  build at ./3_build.sh time - this script needs no per-board changes.
#
#      ./5_debug.sh               plain GDB prompt
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
#  Several J-Links attached: PROBE_SERIAL=<serial> ./5_debug.sh
# ===========================================================================
set -euo pipefail
FIREFLY_USB=1
source "$(dirname "$0")/variables.sh"

[ -d "$BUILD_DIR" ] || { c_err "!!! No build - run ./3_build.sh first"; exit 1; }

select_probe || exit 1
args=(west debug --build-dir "$BUILD_DIR" -r "$FLASH_RUNNER" "${PROBE_ARGS[@]}")
args+=("$@")

cd "$WORKSPACE_DIR"
if ! ncs "${args[@]}"; then
    c_err ""
    c_err "!!! Debug session failed. Check in order (same as ./4_flash.sh):"
    c_err "    1. DK powered, and the J-Link still attached? ./x_usb.sh list"
    c_err "    2. Another program using the probe? Only one J-Link client at a time."
    c_err "    3. Device protected? See ./4_flash.sh's recover hint."
    exit 1
fi
