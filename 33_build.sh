#!/usr/bin/env bash
# ===========================================================================
#  33. Build for the Fibocom LE270 modem target (external, uart21)
# ===========================================================================
#  Thin wrapper around 3_build.sh with TARGET fixed to nrf54lm20dk and MODEM
#  fixed to le270 - see firefly-app/conf/modem_le270.conf and
#  firefly-app/boards/le270.overlay for the modem's own conf/devicetree
#  (same physical uart21/PWRKEY/RESET_N/DTR pins as the EG800Z - only one
#  external modem is ever populated on the DK at a time), and variables.sh
#  for how MODEM is layered onto the build.
#
#      ./33_build.sh              # unsigned development image
#      ./33_build.sh -p           # pristine rebuild
#      ./33_build.sh release -p   # signed MCUboot image
# ===========================================================================
set -euo pipefail
export TARGET=nrf54lm20dk
export MODEM=le270
exec "$(dirname "$0")/3_build.sh" "$@"
