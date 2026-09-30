#!/usr/bin/env bash
# ===========================================================================
#  42. Flash the Quectel EG800Z modem target (external, uart21)
# ===========================================================================
#  Thin wrapper around 4_flash.sh with TARGET/MODEM fixed to match what
#  32_build.sh built. See 4_flash.sh for the JLinkRemoteServer setup this
#  needs on the Windows side.
#
#      ./42_flash.sh
# ===========================================================================
set -euo pipefail
export TARGET=nrf54lm20dk
export MODEM=eg800z
exec "$(dirname "$0")/4_flash.sh" "$@"
