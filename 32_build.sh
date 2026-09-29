#!/usr/bin/env bash
# ===========================================================================
#  32. Build for the Quectel EG800Z modem target (external, uart21)
# ===========================================================================
#  Thin wrapper around 3_build.sh with TARGET fixed to nrf54lm20dk and MODEM
#  fixed to eg800z - see firefly-app/conf/modem_eg800z.conf and
#  firefly-app/boards/eg800z.overlay for the modem's own conf/devicetree,
#  and variables.sh for how MODEM is layered onto the build.
#
#      ./32_build.sh              # unsigned development image
#      ./32_build.sh -p           # pristine rebuild
#      ./32_build.sh release -p   # signed MCUboot image
# ===========================================================================
set -euo pipefail
export TARGET=nrf54lm20dk
export MODEM=eg800z
exec "$(dirname "$0")/3_build.sh" "$@"
