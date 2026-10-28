#!/usr/bin/env bash
# ===========================================================================
#  MCUboot signing key
# ===========================================================================
#  nRF54L: ECDSA-P256 (ed25519 also supported). Not RSA, unlike the i.MX side.
#
#      ./x_keygen.sh            create $BOOT_KEY_FILE (refuses if it exists)
#      ./x_keygen.sh --force    replace it; the old key is kept as
#                               <key>.<date>.bak, never deleted
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

force=0
case "${1:-}" in
    "")      ;;
    --force) force=1 ;;
    *)       c_err "usage: $0 [--force]"; exit 2 ;;
esac

if [ -e "$BOOT_KEY_FILE" ]; then
    if [ "$force" != 1 ]; then
        c_err "!!! A key already exists: $BOOT_KEY_FILE"
        c_err "    Devices signed with it reject updates signed with a new one."
        c_err "    To replace it anyway (the old key is kept as a .bak): $0 --force"
        exit 1
    fi
    backup="$BOOT_KEY_FILE.$(date +%Y%m%d-%H%M%S).bak"
    mv "$BOOT_KEY_FILE" "$backup"
    c_warn "Old key moved to $backup - keep it while devices signed with it exist."
fi

mkdir -p "$(dirname "$BOOT_KEY_FILE")"
# Created private from the start, not chmod'ed after imgtool has written it.
( umask 077
  ncs python "$WORKSPACE_DIR/bootloader/mcuboot/scripts/imgtool.py" \
      keygen -k "$BOOT_KEY_FILE" -t "$BOOT_KEY_TYPE" )
chmod 600 "$BOOT_KEY_FILE"

c_ok ""
c_ok "Generated $BOOT_KEY_TYPE key: $BOOT_KEY_FILE"
echo "-> store it somewhere safe (private repo / secrets vault)"
echo "-> losing it means you can no longer sign updates for shipped devices"
