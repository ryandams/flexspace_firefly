#!/usr/bin/env bash
# ===========================================================================
#  52. Debug the Quectel EG800Z modem target (external, uart21)
# ===========================================================================
#  Thin wrapper around 5_debug.sh with TARGET/MODEM fixed to match what
#  32_build.sh built.
#
#      ./52_debug.sh
# ===========================================================================
set -euo pipefail
export TARGET=nrf54lm20dk
export MODEM=eg800z
exec "$(dirname "$0")/5_debug.sh" "$@"
