#!/usr/bin/env bash
# Build modes: app-target (default) or release (MCUboot + signed image).
set -euo pipefail
source "$(dirname "$0")/variables.sh"

mode="app-target"
pristine="$PRISTINE"
while [ $# -gt 0 ]; do
    case "$1" in
        app-target|release) mode="$1" ;;
        -p) pristine=always ;;
        *) c_err "usage: $0 [app-target|release] [-p]"; exit 2 ;;
    esac
    shift
done

[ -d "$WEST_DIR" ] || { c_err "No workspace - run ./2_workspace.sh"; exit 1; }
drop_foreign_build_dir "$BUILD_DIR"

# -DAPP_DIR=<absolute path> is belt-and-suspenders: sysbuild's top-level
# CMakeLists.txt (zephyr/share/sysbuild/CMakeLists.txt) is *supposed* to pick
# this up automatically from the positional app-dir west build is given, but
# for at least nrf93m1dk/nrf54l15/cpuapp it silently fell back to building
# zephyr/samples/hello_world instead of firefly-app with no error at all -
# passing it explicitly sidesteps whatever west-side resolution that was.
extra_conf_file="conf/development.conf"
if [ -n "${MODEM_CONF_FILE:-}" ]; then
    extra_conf_file="$extra_conf_file;$MODEM_CONF_FILE"
fi

args=(west build -b "$BOARD_NAME" "$APP_DIR" --build-dir "$BUILD_DIR" -p "$pristine")
args+=(-- -DEXTRA_CONF_FILE="$extra_conf_file" -DAPP_DIR="$PROJECT_DIR")
if [ -n "${MODEM_OVERLAY_FILE:-}" ]; then
    args+=(-DEXTRA_DTC_OVERLAY_FILE="$MODEM_OVERLAY_FILE")
fi

if [ "$mode" = release ]; then
    [ -f "$BOOT_KEY_FILE" ] || {
        c_err "Release signing key missing: $BOOT_KEY_FILE (run ./x_keygen.sh)"; exit 1;
    }
    release_conf_file="conf/production.conf"
    if [ -n "${MODEM_CONF_FILE:-}" ]; then
        release_conf_file="$release_conf_file;$MODEM_CONF_FILE"
    fi
    args=(west build -b "$BOARD_NAME" "$APP_DIR" --build-dir "$BUILD_DIR" -p "$pristine"
          --sysbuild -- -DEXTRA_CONF_FILE="$release_conf_file" -DAPP_DIR="$PROJECT_DIR"
          -DSB_EXTRA_CONF_FILE="$PROJECT_DIR/sysbuild-release.conf"
          "-DSB_CONFIG_BOOT_SIGNATURE_KEY_FILE=\"$BOOT_KEY_FILE\"")
    if [ -n "${MODEM_OVERLAY_FILE:-}" ]; then
        args+=(-DEXTRA_DTC_OVERLAY_FILE="$MODEM_OVERLAY_FILE")
    fi
fi

cd "$WORKSPACE_DIR"
ncs "${args[@]}"

artifacts=(
    "$BUILD_DIR/$APP_IMAGE_NAME/zephyr/zephyr.elf"
    "$BUILD_DIR/$APP_IMAGE_NAME/zephyr/zephyr.hex"
    "$BUILD_DIR/$APP_IMAGE_NAME/zephyr/zephyr.bin"
    "$BUILD_DIR/merged.hex"
    "$BUILD_DIR/$APP_IMAGE_NAME/zephyr/zephyr.signed.bin"
    "$BUILD_DIR/mcuboot/zephyr/zephyr.hex"
    "$BUILD_DIR/dfu_application.zip"
)
found=0
for file in "${artifacts[@]}"; do
    if [ -f "$file" ]; then printf '  %10s  %s\n' "$(stat -c%s "$file")B" "$file"; found=1; fi
done
[ "$found" -eq 1 ] || { c_err "Build succeeded but no expected artifacts were found"; exit 1; }
