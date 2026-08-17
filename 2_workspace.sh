#!/usr/bin/env bash
# ===========================================================================
#  2. West workspace
# ===========================================================================
#    ./2_workspace.sh        create / update
#    ./2_workspace.sh -r     reinit (old tree renamed to _old, app preserved)
#
#  No python venv: the NCS toolchain bundle ships a python that already has
#  west and every requirements.txt installed.
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"

reinit=0
[ "${1:-}" = "-r" ] && { reinit=1; c_info "=> workspace reinitialization"; }

if [ "$reinit" = 1 ] && [ -d "$WORKSPACE_DIR" ]; then
    rm -rf "${WORKSPACE_DIR}_old"
    # The app repo lives inside the workspace; a naive rename would carry all
    # your source into _old. Stash it, rename, put it back.
    stash=""
    if [ -d "$PROJECT_DIR" ]; then
        stash="$FIREFLY_ROOT/.${PROJECT_NAME}_stash"
        rm -rf "$stash"
        c_warn "Preserving app repo across reinit: $PROJECT_NAME"
        mv "$PROJECT_DIR" "$stash"
    fi
    mv "$WORKSPACE_DIR" "${WORKSPACE_DIR}_old"
    if [ -n "$stash" ]; then
        mkdir -p "$WORKSPACE_DIR"
        mv "$stash" "$PROJECT_DIR"
        c_ok "Restored app repo to $PROJECT_DIR"
    fi
fi

# ---- manifest repair ------------------------------------------------------
#  A workspace can exist while pointing at the WRONG manifest repository -
#  e.g. initialised from upstream sdk-nrf, so west.yml's SDK pin and
#  name-allowlist are silently ignored. Builds still work, because
#  `west build <path>` never consults the manifest.
if [ -f "$WEST_DIR/config" ]; then
    current="$(awk -F= '/^[[:space:]]*path[[:space:]]*=/ {gsub(/ /,"",$2); print $2; exit}' "$WEST_DIR/config")"
    if [ -n "$current" ] && [ "$current" != "$PROJECT_NAME" ]; then
        c_warn "Manifest repo is '$current', expected '$PROJECT_NAME'."
        c_warn "  $PROJECT_NAME/west.yml is being ignored - repairing."
        c_warn "  (checkouts are kept; only .west is recreated)"
        rm -rf "$WEST_DIR"
    fi
fi

# ---- west init ------------------------------------------------------------
if [ ! -d "$WEST_DIR" ]; then
    c_info "Creating workspace: $WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR"

    if [ -f "$PROJECT_DIR/west.yml" ]; then
        # local manifest repo; `west init -l` wants a git repository
        if [ ! -d "$PROJECT_DIR/.git" ]; then
            c_info "Initializing git repo in $PROJECT_DIR"
            git -C "$PROJECT_DIR" init -q
            git -C "$PROJECT_DIR" add -A
            git -C "$PROJECT_DIR" -c user.email=dev@local -c user.name=dev \
                commit -qm "scaffold firefly app"
        fi
        c_info "west init -l $PROJECT_NAME"
        ( cd "$WORKSPACE_DIR" && ncs west init -l "$PROJECT_NAME" )
    elif [ -n "$PROJECT_GIT_URL" ]; then
        c_info "west init -m $PROJECT_GIT_URL @ $PROJECT_GIT_REV"
        ( cd "$(dirname "$WORKSPACE_DIR")" && \
          ncs west init -m "$PROJECT_GIT_URL" --mr "$PROJECT_GIT_REV" "$(basename "$WORKSPACE_DIR")" )
    else
        c_err "!!! No $PROJECT_DIR/west.yml and no PROJECT_GIT_URL. Nothing to init from."
        exit 1
    fi
else
    c_ok "Workspace already initialized: $WEST_DIR"
fi

# ---- update ---------------------------------------------------------------
cd "$WORKSPACE_DIR"
c_info "west update  (first run clones the NCS tree - several GB)"
ncs west update

ncs west patch apply || true

if [ "$WEST_ZEPHYR_EXPORT" = 1 ]; then
    ncs west zephyr-export
else
    echo "Skipping 'west zephyr-export' - west build resolves Zephyr from the workspace."
fi

ncs west list || true
c_ok ""
c_ok "Workspace ready. Next: ./3_build.sh   or   ./7_test.sh"
