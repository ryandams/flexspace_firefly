#!/usr/bin/env bash
# ===========================================================================
#  31. Build for the nRF93M1 modem target (on-board, nrf93m1dk)
# ===========================================================================
#  Thin wrapper around 3_build.sh with TARGET fixed to nrf93m1dk - the
#  nRF93M1 DK's on-board modem, no external wiring needed. See variables.sh
#  for what TARGET selects and 32_build.sh/33_build.sh for the other two
#  supported modems.
#
#      ./31_build.sh              # unsigned development image
#      ./31_build.sh -p           # pristine rebuild
#      ./31_build.sh release -p   # signed MCUboot image
# ===========================================================================
set -euo pipefail
export TARGET=nrf93m1dk
exec "$(dirname "$0")/3_build.sh" "$@"
