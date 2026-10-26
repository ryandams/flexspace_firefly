#!/usr/bin/env bash
# ===========================================================================
#  0. Docker build environment (replaces 0_prereqs.sh + 1_toolchain.sh)
# ===========================================================================
#    ./0_docker.sh install      Docker Engine into this WSL2 distro (sudo)
#    ./0_docker.sh build        build the firefly-dev image (~10 min, ~7 GB)
#    ./0_docker.sh build --if-stale   ...only if missing or out of date
#    ./0_docker.sh shell        interactive shell in the container
#
#  After `install` + `build`, run ./2_workspace.sh and carry on as before -
#  every numbered script re-launches itself inside the container (see the
#  "Container" section of variables.sh). You rarely need `build` by hand: a
#  script that finds the image missing or stale rebuilds it first.
#
#  Docker Engine runs inside WSL2 itself, not Docker Desktop: no Windows-side
#  install, no licence question, and the bind-mounted workspace stays on the
#  ext4 filesystem at full speed.
# ===========================================================================
set -euo pipefail
FIREFLY_HOST_ONLY=1
source "$(dirname "$0")/variables.sh"

[ -z "${FIREFLY_CONTAINER:-}" ] || { c_err "Run this from WSL, not inside the container."; exit 1; }

JLINK_DEB="JLink_Linux_${JLINK_VERSION}_x86_64.deb"
VENDOR_DIR="$FIREFLY_ROOT/docker/vendor"

do_install() {
    [ "$(wsl_version)" = 2 ] || c_warn "Not WSL2 - continuing, but this script is written for WSL2."

    if [ "$(ps -p 1 -o comm= 2>/dev/null)" != systemd ]; then
        c_err "!!! systemd is not running (needed to start dockerd). Add to /etc/wsl.conf:"
        c_err "        [boot]"
        c_err "        systemd=true"
        c_err "    then from Windows: wsl --shutdown, and reopen WSL."
        exit 1
    fi

    case "$(command -v docker 2>/dev/null)" in
        /mnt/*|*docker-desktop*)
            c_warn "!!! 'docker' resolves to Docker Desktop's WSL integration. Turn that"
            c_warn "    integration off for this distro (Docker Desktop > Settings >"
            c_warn "    Resources > WSL integration) so the two engines do not fight." ;;
    esac

    # Ubuntu's own packages rather than Docker's apt repo: no third-party key,
    # and they exist on day one for every Ubuntu release (Docker's repo lags).
    c_info "Installing Docker Engine..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends docker.io docker-buildx
    sudo systemctl enable --now docker

    if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
        c_ok "$USER is already in the docker group."
    else
        sudo usermod -aG docker "$USER"
        c_warn ""
        c_warn "Added $USER to the docker group. It takes effect in a new login:"
        c_warn "from Windows run wsl --shutdown (closing terminals is not enough while"
        c_warn "VS Code is connected), reopen, then: ./0_docker.sh build"
        return
    fi
    c_ok ""
    c_ok "Docker ready. Next: ./0_docker.sh build"
}

# The J-Link pack is behind SEGGER's EULA, so it cannot be fetched by script.
# Look in the obvious place a browser on Windows would have saved it.
find_jlink_deb() {
    [ -f "$VENDOR_DIR/$JLINK_DEB" ] && return 0
    local f
    for f in /mnt/c/Users/*/Downloads/"$JLINK_DEB" "$HOME/Downloads/$JLINK_DEB"; do
        if [ -f "$f" ]; then
            c_info "Using $f"
            mkdir -p "$VENDOR_DIR"
            cp "$f" "$VENDOR_DIR/"
            return 0
        fi
    done
    c_err "!!! $JLINK_DEB not found."
    c_err "    Download the 64-bit DEB installer for J-Link $JLINK_VERSION from"
    c_err "    https://www.segger.com/downloads/jlink/#J-LinkSoftwareAndDocumentationPack"
    c_err "    (Older versions link at the bottom of that page.) Save it into your"
    c_err "    Windows Downloads folder or $VENDOR_DIR/, then re-run."
    return 1
}

do_build() {
    if [ "${1:-}" = --if-stale ] && firefly_image_current; then
        c_ok "Image $FIREFLY_IMAGE is up to date."
        return
    fi
    command -v docker >/dev/null 2>&1 || { c_err "!!! docker not found - run ./0_docker.sh install"; exit 1; }
    if ! docker info >/dev/null 2>&1; then
        # Group membership is fixed at login. VS Code's WSL server keeps the
        # distro alive, so closing terminals alone does not start a new login.
        if id -nG "$USER" | tr ' ' '\n' | grep -qx docker \
           && ! id -nG | tr ' ' '\n' | grep -qx docker; then
            c_err "!!! You are in the docker group, but this session predates it."
            c_err "    From Windows: wsl --shutdown, then reopen VS Code / WSL."
        else
            c_err "!!! Cannot talk to the Docker daemon. Not in the docker group"
            c_err "    (./0_docker.sh install), or the service is down"
            c_err "    (sudo systemctl start docker)."
        fi
        exit 1
    fi
    find_jlink_deb

    c_info "Building $FIREFLY_IMAGE (NCS $NCS_VERSION, toolchain $NCS_TOOLCHAIN_BUNDLE_ID)..."
    docker build \
        --build-arg NRFUTIL_VERSION="$NRFUTIL_VERSION" \
        --build-arg NRFUTIL_SDK_MANAGER_VERSION="$NRFUTIL_SDK_MANAGER_VERSION" \
        --build-arg NRFUTIL_DEVICE_VERSION="$NRFUTIL_DEVICE_VERSION" \
        --build-arg NCS_VERSION="$NCS_VERSION" \
        --build-arg NCS_TOOLCHAIN_BUNDLE_ID="$NCS_TOOLCHAIN_BUNDLE_ID" \
        --build-arg JLINK_VERSION="$JLINK_VERSION" \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        --label firefly.hash="$(firefly_image_hash)" \
        -t "$FIREFLY_IMAGE" \
        "$FIREFLY_ROOT/docker"

    # Old images are left dangling on every rebuild; they are ~7 GB each.
    docker image prune -f --filter label=firefly.hash >/dev/null || true
    c_ok ""
    c_ok "Image ready. Next: ./2_workspace.sh   (or ./3_build.sh if the workspace exists)"
}

case "${1:-}" in
    install) do_install ;;
    build)   shift; do_build "$@" ;;
    shell)   firefly_docker_exec bash ;;
    *)       c_err "usage: $0 install | build [--if-stale] | shell"; exit 2 ;;
esac
