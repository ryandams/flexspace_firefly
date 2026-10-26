# shellcheck shell=bash
# ===========================================================================
#  firefly - Nordic nRF54LM20 / nRF Connect SDK, built and tested in WSL2
# ===========================================================================
#  Sourced by every numbered script. Not executable on its own.
#
#  Why there is no environment-isolation machinery here:
#  the Windows scripts had to strip ZEPHYR_SDK_INSTALL_DIR because
#  vestfrost-level-3 sets it machine-wide. That is a *Windows* environment
#  variable and does not exist inside WSL2, so the two projects cannot
#  collide. Different OS, different environment.
# ===========================================================================

set -o pipefail

FIREFLY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
#  Toolchain
# ---------------------------------------------------------------------------
#  nRF54LM20 needs NCS v3.2.0 or newer. `nrfutil sdk-manager search` is the
#  authoritative list - not any documentation page.
#
#  TEMPORARY MISMATCH: firefly-app/west.yml pins sdk-nrf main at an exact
#  commit for nRF93M1 modem support. That manifest selects the matching Zephyr
#  and modules. Nordic has not published a newer installable toolchain bundle,
#  so v3.4.0 compiles this development snapshot. Re-align both pins with the
#  first stable NCS release containing nRF93M1 support.
NCS_VERSION="${NCS_VERSION:-v3.4.0}"

NRFUTIL_DIR="${NRFUTIL_DIR:-$HOME/.local/bin}"
NRFUTIL="$NRFUTIL_DIR/nrfutil"
NRFUTIL_URL="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil"
NRFUTIL_COMMANDS=(sdk-manager device)

#  Exact pins for the container image (docker/Dockerfile). Bump these
#  deliberately - every developer's image rebuilds on their next script run.
#  NCS_TOOLCHAIN_BUNDLE_ID is what `nrfutil sdk-manager toolchain list`
#  shows for NCS_VERSION; pinning the bundle, not just the version, stops a
#  patched bundle for the same release slipping into newer images.
NRFUTIL_VERSION="8.2.1"
NRFUTIL_SDK_MANAGER_VERSION="1.16.1"
NRFUTIL_DEVICE_VERSION="2.20.0"
NCS_TOOLCHAIN_BUNDLE_ID="fbf7391cab"
JLINK_VERSION="V966"                  # JLink_Linux_V966_x86_64.deb

# ---------------------------------------------------------------------------
#  Container
# ---------------------------------------------------------------------------
#  Every numbered script runs inside the firefly-dev image. Run from a WSL
#  shell, a script re-launches itself in a throwaway container (see the end
#  of this file); run from the dev container's own terminal it just runs.
#  The repo is bind-mounted at the same path for everyone, so build trees,
#  compile_commands.json and launch.json are identical across machines.
#
#     FIREFLY_NATIVE=1 ./3_build.sh    escape hatch: run on raw WSL with a
#                                      toolchain from 0_prereqs/1_toolchain
FIREFLY_IMAGE="${FIREFLY_IMAGE:-firefly-dev:latest}"
FIREFLY_CONTAINER_ROOT="/workspaces/firefly"

#  Variables a script's caller may export that must reach the container.
#  BOOT_KEY_FILE is translated when it points inside the repo.
FIREFLY_ENV_PASSTHROUGH=(TARGET MODEM BOARD_NAME SIM_BOARD_NAME PRISTINE
                         FLASH_RUNNER JLINK_HOST PROBE_SERIAL BOOT_KEY_FILE)

# ---------------------------------------------------------------------------
#  Workspace
# ---------------------------------------------------------------------------
WORKSPACE_DIR="$FIREFLY_ROOT/ncsworkspace"
WEST_DIR="$WORKSPACE_DIR/.west"
ZEPHYR_BASE_DIR="$WORKSPACE_DIR/zephyr"

PROJECT_NAME="firefly-app"            # matches `self: path:` in west.yml
PROJECT_GIT_REPO="firefly-app"        # repo name on GitHub
PROJECT_GIT_URL="https://github.com/ryandams/firefly-app.git"
PROJECT_GIT_REV="main"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# `west zephyr-export` writes the shared CMake user package registry.
# Not needed for west build - it resolves Zephyr from the workspace - but
# nRF Connect for VS Code's own SDK detection reads exactly this registry
# to populate its "Manage SDKs" list. Skipping it left the extension
# stuck on "Install an SDK to get started" despite a working toolchain.
WEST_ZEPHYR_EXPORT=1

# ---------------------------------------------------------------------------
#  Build
# ---------------------------------------------------------------------------
#  TARGET selects which real hardware board 3_build.sh/4_flash.sh/5_debug.sh/
#  6_menuconfig.sh operate on. Each gets its own build directory, so
#  switching targets never forces a pristine rebuild of the other:
#
#     TARGET=nrf54lm20dk (default)  nrf54lm20dk/nrf54lm20a/cpuapp
#                                    (NPU-less A variant - this project's
#                                    main board; no modem wired up by
#                                    default - see MODEM below)
#     TARGET=nrf93m1dk               nrf93m1dk/nrf54l15/cpuapp
#                                    (on-board nRF93M1 modem, no external
#                                    wiring needed - default board revision
#                                    0.3.0 already matches: led0..led2,
#                                    sw0..sw1)
#
#  Usage:  TARGET=nrf93m1dk ./3_build.sh
#          TARGET=nrf93m1dk ./4_flash.sh
#          TARGET=nrf93m1dk ./5_debug.sh
#
#  Other nRF54LM20 DK board targets, for reference (not wired up as a
#  TARGET here - override BOARD_NAME directly if you need one of these):
#     nrf54lm20dk/nrf54lm20b/cpuapp   <- B variant, with NPU
#     nrf54lm20dk/nrf54lm20a/cpuflpr  <- RISC-V FLPR core (needs sysbuild)
TARGET="${TARGET:-nrf54lm20dk}"

#  MODEM only applies when TARGET=nrf54lm20dk: firefly-app's board files for
#  that target carry no modem wiring of their own (see
#  firefly-app/boards/nrf54lm20dk_nrf54lm20a_cpuapp.{conf,overlay}) - each
#  externally-wired modem instead lives in its own additive
#  conf/modem_<MODEM>.conf + boards/<MODEM>.overlay pair inside firefly-app,
#  layered on with EXTRA_CONF_FILE/EXTRA_DTC_OVERLAY_FILE below. Leave unset
#  (the default) to build nrf54lm20dk with no modem at all
#  (FIREFLY_MODEM_SERVICE_NONE).
#
#     MODEM=eg800z   Quectel EG800Z, external, uart21 - no CMUX, drives the
#                    modem directly via modemEg800zPpp.cpp.
#     MODEM=le270    Fibocom LE270, external, uart21 (same physical pins as
#                    eg800z - only one external modem is ever populated at
#                    once) - supports CMUX, uses the generic modem_cellular
#                    transport instead.
#
#  Usage:  TARGET=nrf54lm20dk MODEM=eg800z ./3_build.sh
#          31/32/33_build.sh wrap the three supported (TARGET, MODEM)
#          combinations - see README.md.
#
#  An nRF93M1 module wired externally to nrf54lm20dk (over uart30, rather
#  than the on-board nrf93m1dk target above) is also available as
#  MODEM=nrf93m1_ext, with no numbered build script of its own yet.
MODEM="${MODEM:-}"

APP_DIR="$PROJECT_NAME"
BUILDS_DIR="$WORKSPACE_DIR/builds"

case "$TARGET" in
    nrf54lm20dk)
        BOARD_NAME="${BOARD_NAME:-nrf54lm20dk/nrf54lm20a/cpuapp}"
        if [ -n "$MODEM" ]; then
            BUILD_DIR="$BUILDS_DIR/build_$MODEM"
            MODEM_CONF_FILE="$PROJECT_DIR/conf/modem_$MODEM.conf"
            MODEM_OVERLAY_FILE="$PROJECT_DIR/boards/$MODEM.overlay"
            [ -f "$MODEM_CONF_FILE" ] || {
                echo "!!! Unknown MODEM '$MODEM' - no $MODEM_CONF_FILE" >&2
                return 1 2>/dev/null || exit 1
            }
            [ -f "$MODEM_OVERLAY_FILE" ] || {
                echo "!!! Unknown MODEM '$MODEM' - no $MODEM_OVERLAY_FILE" >&2
                return 1 2>/dev/null || exit 1
            }
        else
            BUILD_DIR="$BUILDS_DIR/build"
            MODEM_CONF_FILE=""
            MODEM_OVERLAY_FILE=""
        fi
        ;;
    nrf93m1dk)
        BOARD_NAME="${BOARD_NAME:-nrf93m1dk/nrf54l15/cpuapp}"
        BUILD_DIR="$BUILDS_DIR/build_nrf93m1dk"
        MODEM_CONF_FILE=""
        MODEM_OVERLAY_FILE=""
        ;;
    *)
        echo "!!! Unknown TARGET '$TARGET' (nrf54lm20dk | nrf93m1dk)" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac

#  native_sim builds 32-bit by default; keep it that way so pointer width and
#  struct padding match the Cortex-M. Needs gcc-multilib (see 0_prereqs.sh).
SIM_BOARD_NAME="${SIM_BOARD_NAME:-native_sim}"
SIM_BUILD_DIR="$BUILDS_DIR/build_sim"

#  "auto" lets west decide: incremental unless the build dir is missing or
#  stale for the current board/config. ./3_build.sh -p forces "always".
PRISTINE="${PRISTINE:-auto}"          # always | auto | never
SYSBUILD=0

# ---------------------------------------------------------------------------
#  Flash / debug
# ---------------------------------------------------------------------------
#  WSL2 has no native USB, so the DK's debug probe is not visible here.
#  Rather than fighting usbipd, run JLinkRemoteServer on Windows and reach it
#  over TCP. Set JLINK_HOST to the Windows host IP (see 4_flash.sh, which can
#  work it out from /etc/resolv.conf).
FLASH_RUNNER="${FLASH_RUNNER:-jlink}"
JLINK_HOST="${JLINK_HOST:-}"          # empty => auto-detect the Windows host
PROBE_SERIAL="${PROBE_SERIAL:-}"

# ---------------------------------------------------------------------------
#  Signing
# ---------------------------------------------------------------------------
KEYS_DIR="$FIREFLY_ROOT/keys"
BOOT_KEY_TYPE="ecdsa-p256"            # nRF54L; not RSA as on the i.MX side
BOOT_KEY_FILE="${BOOT_KEY_FILE:-$KEYS_DIR/boot_key.pem}"

#  sysbuild names image directories after the CMake project() name.
APP_IMAGE_NAME="firefly-app"
MERGED_HEX="$BUILD_DIR/merged.hex"

# ===========================================================================
#  Helpers
# ===========================================================================
c_info()  { printf '\033[36m%s\033[0m\n' "$*"; }
c_ok()    { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn()  { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }

nrfutil_bin() {
    if command -v nrfutil >/dev/null 2>&1; then command -v nrfutil
    elif [ -x "$NRFUTIL" ];              then echo "$NRFUTIL"
    else return 1; fi
}

# Run a command inside the NCS toolchain environment.
#   ncs west build -b "$BOARD_NAME" ...
ncs() {
    local bin
    if ! bin="$(nrfutil_bin)"; then
        c_err "!!! nrfutil not found - run ./0_prereqs.sh first"
        return 1
    fi
    c_info "[ncs $NCS_VERSION] $*"
    "$bin" sdk-manager toolchain launch --ncs-version "$NCS_VERSION" -- "$@"
}

# Run a command, capture ALL of its output, then print the first N lines.
#
# Never pipe nrfutil - or anything it launches - straight into `head`: head
# closes the pipe after N lines, the child process takes SIGPIPE, and nrfutil
# reports "Launched terminated early". With `set -o pipefail` in force that
# turns a cosmetic version print into a failed script.
#
# Command substitution reads to EOF, so nothing ever sees a broken pipe.
head_of() {
    local n="$1"; shift
    local out
    out="$("$@" 2>&1)" || true
    printf '%s\n' "$out" | head -n "$n"
}

# A CMake build directory only works at the path it was configured at: its
# cache pins absolute paths, and even west's "make it pristine" step runs a
# script from the old ZEPHYR_BASE. Build dirs made on raw WSL (/home/<you>/...)
# or another machine are therefore useless here - they are generated output,
# so remove them rather than fail.
drop_foreign_build_dir() {
    local dir="$1" cache="$1/CMakeCache.txt" was
    [ -f "$cache" ] || return 0
    was="$(sed -n 's/^CMAKE_CACHEFILE_DIR:INTERNAL=//p' "$cache")"
    [ -n "$was" ] && [ "$was" != "$dir" ] || return 0
    c_warn "Removing $dir - it was configured at $was"
    rm -rf "$dir"
}

# Newest stable NCS release, pre-releases excluded.
ncs_latest_stable() {
    local bin; bin="$(nrfutil_bin)" || return 1
    "$bin" sdk-manager search 2>/dev/null \
        | awk '/^[[:space:]]*nrf[[:space:]]+v[0-9]/ {print $2}' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V | tail -1
}

# Which WSL are we on?  Prints: 2 | 1 | none
#
# Careful: /proc/version contains "Microsoft" on BOTH WSL1 and WSL2, so the
# obvious grep is wrong. WSL1 is a syscall translation layer with no real
# kernel - west and native_sim are not supported there.
#
# Signals, most reliable first:
#   uname -r  ->  WSL2: "...-microsoft-standard-WSL2"   WSL1: "...-Microsoft"
#   /dev/vsock exists only on WSL2 (Hyper-V socket used for interop)
#   /run/WSL/ exists only on WSL2
wsl_version() {
    grep -qi microsoft /proc/version 2>/dev/null || { echo none; return; }

    local r; r="$(uname -r)"
    case "$r" in
        *WSL2*|*wsl2*)              echo 2; return ;;
        *microsoft-standard*)       echo 2; return ;;
    esac

    if [ -e /dev/vsock ] || [ -d /run/WSL ]; then echo 2; return; fi

    echo 1
}

# Windows host IP as seen from WSL2 - for JLinkRemoteServer.
windows_host_ip() {
    if [ -n "$JLINK_HOST" ]; then echo "$JLINK_HOST"; return; fi
    ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

# ===========================================================================
#  Container dispatch
# ===========================================================================

# Fingerprint of everything that goes into the image. Stamped on it as a label
# at build time; a mismatch means docker/Dockerfile or a pin changed since.
firefly_image_hash() {
    {
        cat "$FIREFLY_ROOT/docker/Dockerfile"
        echo "$NRFUTIL_VERSION $NRFUTIL_SDK_MANAGER_VERSION $NRFUTIL_DEVICE_VERSION"
        echo "$NCS_VERSION $NCS_TOOLCHAIN_BUNDLE_ID $JLINK_VERSION $(id -u):$(id -g)"
    } | sha256sum | cut -c1-16
}

firefly_image_current() {
    local have
    have="$(docker image inspect -f '{{ index .Config.Labels "firefly.hash" }}' \
            "$FIREFLY_IMAGE" 2>/dev/null)" || return 1
    [ "$have" = "$(firefly_image_hash)" ]
}

# Host path under the repo -> the same path inside the container.
firefly_container_path() {
    case "$1" in
        "$FIREFLY_ROOT")   echo "$FIREFLY_CONTAINER_ROOT" ;;
        "$FIREFLY_ROOT"/*) echo "$FIREFLY_CONTAINER_ROOT${1#"$FIREFLY_ROOT"}" ;;
        *) return 1 ;;
    esac
}

# Run a command in a fresh container with the repo mounted. Never returns.
#
#   --network host     the container shares WSL's network, so
#                      windows_host_ip() and JLinkRemoteServer work unchanged
#   SYS_PTRACE +
#   seccomp=unconfined LeakSanitizer (./7_test.sh sanitizer) and gdb on
#                      native_sim both need ptrace/personality
firefly_docker_exec() {
    command -v docker >/dev/null 2>&1 || {
        c_err "!!! docker not found - run ./0_docker.sh install"; exit 1; }
    if ! firefly_image_current; then
        c_warn "Image $FIREFLY_IMAGE is missing or out of date - building it."
        "$FIREFLY_ROOT/0_docker.sh" build || exit 1
    fi

    local tty=(-i) envs=() v p
    [ -t 0 ] && [ -t 1 ] && tty=(-it)
    # Only what the caller exported (e.g. 31_build.sh's TARGET) - not the
    # defaults this file filled in, which the container works out itself.
    for v in "${FIREFLY_ENV_PASSTHROUGH[@]}"; do
        [[ "$(declare -p "$v" 2>/dev/null)" == "declare -x"* ]] || continue
        p="${!v}"
        if [ "$v" = BOOT_KEY_FILE ]; then
            p="$(firefly_container_path "$(realpath -m "$p")")" || {
                c_err "!!! BOOT_KEY_FILE must be inside $FIREFLY_ROOT to be visible in the container"
                exit 1
            }
        fi
        envs+=(-e "$v=$p")
    done

    # The image has no git identity; lend it yours for anything committed
    # in there. (Credentials are deliberately not forwarded - push from WSL.)
    local name email
    name="$(git config --get user.name || true)"
    email="$(git config --get user.email || true)"
    [ -z "$name" ]  || envs+=(-e "GIT_AUTHOR_NAME=$name" -e "GIT_COMMITTER_NAME=$name")
    [ -z "$email" ] || envs+=(-e "GIT_AUTHOR_EMAIL=$email" -e "GIT_COMMITTER_EMAIL=$email")

    local wd
    wd="$(firefly_container_path "$PWD")" || wd="$FIREFLY_CONTAINER_ROOT"

    exec docker run --rm "${tty[@]}" --init --network host \
        --cap-add SYS_PTRACE --security-opt seccomp=unconfined \
        -v "$FIREFLY_ROOT:$FIREFLY_CONTAINER_ROOT" -w "$wd" \
        "${envs[@]}" "$FIREFLY_IMAGE" "$@"
}

# A numbered script sourcing this from a WSL shell re-runs itself in the
# container. "$0"/"$@" are the sourcing script's own name and arguments.
# 0_docker.sh sets FIREFLY_HOST_ONLY - it is what builds the container.
if [ -z "${FIREFLY_CONTAINER:-}" ] && [ "${FIREFLY_NATIVE:-0}" != 1 ] \
   && [ "${FIREFLY_HOST_ONLY:-0}" != 1 ]; then
    __script="$(firefly_container_path "$(realpath "$0")")" || {
        c_err "!!! $0 is not inside $FIREFLY_ROOT"; exit 1; }
    firefly_docker_exec "$__script" "$@"
fi
