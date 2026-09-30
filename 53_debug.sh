#!/usr/bin/env bash
# ===========================================================================
#  53. Debug the Fibocom LE270 modem target (external, uart21)
# ===========================================================================
#  Thin wrapper around 5_debug.sh with TARGET/MODEM fixed to match what
#  33_build.sh built.
#
#      ./53_debug.sh
# ===========================================================================
set -euo pipefail
export TARGET=nrf54lm20dk
export MODEM=le270
exec "$(dirname "$0")/5_debug.sh" "$@"
