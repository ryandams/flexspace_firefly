#!/usr/bin/env bash
# ===========================================================================
#  43. Flash the Fibocom LE270 modem target (external, uart21)
# ===========================================================================
#  Thin wrapper around 4_flash.sh with TARGET/MODEM fixed to match what
#  33_build.sh built. See 4_flash.sh for the JLinkRemoteServer setup this
#  needs on the Windows side.
#
#      ./43_flash.sh
# ===========================================================================
set -euo pipefail
export TARGET=nrf54lm20dk
export MODEM=le270
exec "$(dirname "$0")/4_flash.sh" "$@"
