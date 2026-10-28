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

# ---- patches --------------------------------------------------------------
#  firefly-app/zephyr/patches.yml is the source of truth for what is changed
#  in zephyr. `west patch apply` is not idempotent - on an already-patched
#  tree it fails on the first patch - so un-patch, update, re-patch.
#
#  `west patch clean` is `git checkout . && git clean -dfx` in every patched
#  module, which would also discard edits made there by hand. Snapshot each
#  module first; if the re-patched tree differs, the snapshot is kept as
#  refs/firefly/pre-repatch in that module instead of being lost.
PATCH_YML="$PROJECT_DIR/zephyr/patches.yml"
patched_modules=()
if [ -f "$PATCH_YML" ]; then
    mapfile -t patched_modules < <(
        awk '/^[[:space:]]*module:/ {print $2}' "$PATCH_YML" | sort -u)
fi

# Tree hash of the working tree incl. untracked files (not ignored ones),
# without touching the real index.
worktree_tree() {
    local idx; idx="$(mktemp)"
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$1" add -A >/dev/null 2>&1 \
        && GIT_INDEX_FILE="$idx" git -C "$1" write-tree
    rm -f "$idx"
}

declare -A snap_head=() snap_tree=()
for m in "${patched_modules[@]}"; do
    d="$WORKSPACE_DIR/$m"
    [ -d "$d/.git" ] || continue
    snap_head[$m]="$(git -C "$d" rev-parse HEAD)"
    snap_tree[$m]="$(worktree_tree "$d")"
    git -C "$d" update-ref refs/firefly/pre-repatch \
        "$(git -C "$d" -c user.name=firefly -c user.email=firefly@localhost \
            commit-tree "${snap_tree[$m]}" -p HEAD \
            -m "2_workspace.sh: $m before west patch clean")"
done
[ "${#snap_tree[@]}" -eq 0 ] || ncs west patch clean

c_info "west update  (first run clones the NCS tree - several GB)"
ncs west update

ncs west patch apply --roll-back

for m in "${!snap_tree[@]}"; do
    d="$WORKSPACE_DIR/$m"
    if [ "$(git -C "$d" rev-parse HEAD)" = "${snap_head[$m]}" ] \
       && [ "$(worktree_tree "$d")" = "${snap_tree[$m]}" ]; then
        git -C "$d" update-ref -d refs/firefly/pre-repatch
    elif [ "$(git -C "$d" rev-parse HEAD)" = "${snap_head[$m]}" ]; then
        c_warn "!!! $m had changes that are not in patches.yml. They were saved:"
        c_warn "      git -C $d diff refs/firefly/pre-repatch"
        c_warn "    Turn them into a patch, or restore with"
        c_warn "      git -C $d checkout refs/firefly/pre-repatch -- ."
    else
        c_ok "$m moved to a new revision and was re-patched. Its previous state is"
        c_ok "  saved as refs/firefly/pre-repatch in $d"
    fi
done

# Not needed by west build, which resolves Zephyr from the workspace, but
# nRF Connect for VS Code finds SDKs through the CMake package registry this
# writes - without it the extension stays on "Install an SDK to get started".
ncs west zephyr-export

ncs west list || true
c_ok ""
c_ok "Workspace ready. Next: ./3_build.sh   or   ./7_test.sh"
