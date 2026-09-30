#!/usr/bin/env bash
# ===========================================================================
#  51. Debug the nRF93M1 modem target (on-board, nrf93m1dk)
# ===========================================================================
#  Thin wrapper around 5_debug.sh with TARGET fixed to nrf93m1dk - matches
#  what 31_build.sh built.
#
#      ./51_debug.sh
# ===========================================================================
set -euo pipefail
export TARGET=nrf93m1dk
exec "$(dirname "$0")/5_debug.sh" "$@"
