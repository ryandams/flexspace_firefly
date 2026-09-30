#!/usr/bin/env bash
# ===========================================================================
#  41. Flash the nRF93M1 modem target (on-board, nrf93m1dk)
# ===========================================================================
#  Thin wrapper around 4_flash.sh with TARGET fixed to nrf93m1dk - matches
#  what 31_build.sh built. See 4_flash.sh for the JLinkRemoteServer setup
#  this needs on the Windows side.
#
#      ./41_flash.sh
# ===========================================================================
set -euo pipefail
export TARGET=nrf93m1dk
exec "$(dirname "$0")/4_flash.sh" "$@"
