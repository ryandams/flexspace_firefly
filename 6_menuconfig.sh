#!/usr/bin/env bash
# ===========================================================================
#  6. Kconfig UI
# ===========================================================================
#    ./6_menuconfig.sh            terminal UI for the app build
#    ./6_menuconfig.sh sim        ...for the native_sim build
#    ./6_menuconfig.sh app gui    graphical (needs an X server / WSLg)
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"

which="${1:-app}"
ui="${2:-menuconfig}"
[ "$ui" = "gui" ] && ui="guiconfig"

case "$which" in
    sim) dir="$SIM_BUILD_DIR" ;;
    app) dir="$BUILD_DIR" ;;
    *)   c_err "usage: $0 [app|sim] [menuconfig|gui]"; exit 1 ;;
esac

require_workspace
drop_foreign_build_dir "$dir"
[ -d "$dir" ] || { c_err "!!! No build at $dir - build it first"; exit 1; }

cd "$WORKSPACE_DIR"
ncs west build -t "$ui" --build-dir "$dir"
