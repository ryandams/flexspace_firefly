#!/usr/bin/env bash
# ===========================================================================
#  MCUboot signing key
# ===========================================================================
#  nRF54L: ECDSA-P256 (ed25519 also supported). Not RSA, unlike the i.MX side.
#
#  Reference it from sysbuild:
#      SB_CONFIG_BOOT_SIGNATURE_TYPE_ECDSA_P256=y
#      SB_CONFIG_BOOT_SIGNATURE_KEY_FILE="<absolute path>"
#
#  Keys live outside the workspace so `./2_workspace.sh -r` cannot wipe them.
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"
require_workspace   # imgtool comes from the workspace's mcuboot

if [ -f "$BOOT_KEY_FILE" ]; then
    c_warn "!!! A key already exists: $BOOT_KEY_FILE"
    read -r -p "    Overwrite? Devices signed with the old key will reject updates. [y/N] " a
    [ "$a" = "y" ] || { echo "Aborted."; exit 0; }
    rm -rf "$KEYS_DIR"
fi

mkdir -p "$KEYS_DIR"
ncs python "$WORKSPACE_DIR/bootloader/mcuboot/scripts/imgtool.py" \
    keygen -k "$BOOT_KEY_FILE" -t "$BOOT_KEY_TYPE"

if [ -f "$BOOT_KEY_FILE" ]; then
    c_ok ""
    c_ok "Generated $BOOT_KEY_TYPE key: $BOOT_KEY_FILE"
    echo "-> store it somewhere safe (private repo / secrets vault)"
    echo "-> losing it means you can no longer sign updates for shipped devices"
fi
