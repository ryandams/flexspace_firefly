# shellcheck shell=bash
# ===========================================================================
#  firefly - nRF Connect SDK, built and tested in the firefly-dev container
# ===========================================================================
#  Sourced by every numbered script. Not executable on its own. Sourced from
#  WSL, it re-runs the calling script inside the container (see the end of
#  this file).
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
NCS_VERSION="v3.4.0"

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
FIREFLY_IMAGE="firefly-dev:latest"
FIREFLY_CONTAINER_ROOT="/workspaces/firefly"

#  Variables a script's caller may export that must reach the container.
#  BOOT_KEY_FILE is translated when it points inside the repo.
FIREFLY_ENV_PASSTHROUGH=(SIM_BOARD_NAME PRISTINE FLASH_RUNNER PROBE_SERIAL DEVICE_SERIAL BOOT_KEY_FILE)

# ---------------------------------------------------------------------------
#  Workspace
# ---------------------------------------------------------------------------
WORKSPACE_DIR="$FIREFLY_ROOT/ncsworkspace"
WEST_DIR="$WORKSPACE_DIR/.west"

PROJECT_NAME="firefly-app"            # matches `self: path:` in west.yml
PROJECT_GIT_URL="https://github.com/ryandams/firefly-app.git"
PROJECT_GIT_REV="main"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"


# ---------------------------------------------------------------------------
#  Build
# ---------------------------------------------------------------------------
#  The board and modem are chosen in firefly-app/prj.conf
#  (CONFIG_FIREFLY_TARGET_BOARD_* / CONFIG_FIREFLY_TARGET_MODEM_*). The app's
#  CMakeLists.txt adds the modem's files itself; the board has to go to
#  `west build -b`, so it is read here. Switching either one rebuilds the
#  build directory (west goes pristine on a board change by itself).
#  Release builds get their own directory: west's "auto" pristine does not
#  notice changed CMake arguments, so sharing one would carry MCUboot/
#  production settings into the next development build.
APP_DIR="$PROJECT_NAME"
BUILDS_DIR="$WORKSPACE_DIR/builds"
BUILD_DIR="$BUILDS_DIR/build"
RELEASE_BUILD_DIR="$BUILDS_DIR/build_release"

TARGET_BOARD="$(awk '/^CONFIG_FIREFLY_TARGET_BOARD_[A-Z0-9_]+=y$/ {
    sub(/^CONFIG_FIREFLY_TARGET_BOARD_/, ""); sub(/=y$/, ""); print; exit }' \
    "$PROJECT_DIR/prj.conf" 2>/dev/null || true)"
case "$TARGET_BOARD" in
    NRF54LM20DK) BOARD_NAME="nrf54lm20dk/nrf54lm20a/cpuapp" ;;   # NPU-less A variant
    NRF93M1DK)   BOARD_NAME="nrf93m1dk/nrf54l15/cpuapp" ;;
    *)           BOARD_NAME="" ;;                                # no workspace yet
esac

# For scripts that need the west workspace (./2_workspace.sh).
require_workspace() {
    [ -d "$WEST_DIR" ] && return 0
    c_err "!!! No west workspace at $WORKSPACE_DIR - run ./2_workspace.sh first"
    exit 1
}

# For scripts that build for, or talk to, the target board.
require_board() {
    require_workspace
    [ -n "$BOARD_NAME" ] && return 0
    c_err "!!! No known CONFIG_FIREFLY_TARGET_BOARD_*=y in $PROJECT_DIR/prj.conf"
    exit 1
}

#  native_sim builds 32-bit by default; keep it that way so pointer width and
#  struct padding match the Cortex-M. Needs gcc-multilib (docker/Dockerfile).
SIM_BOARD_NAME="${SIM_BOARD_NAME:-native_sim}"
SIM_BUILD_DIR="$BUILDS_DIR/build_sim"

#  "auto" lets west decide: incremental unless the build dir is missing or
#  was configured for another board or source dir. ./3_build.sh -p forces
#  "always".
PRISTINE="${PRISTINE:-auto}"          # always | auto | never

# ---------------------------------------------------------------------------
#  Flash / debug
# ---------------------------------------------------------------------------
#  WSL2 has no USB of its own. usbipd-win (installed by ./x_usb.sh setup)
#  hands the DK's on-board J-Link from Windows to WSL over USB/IP; from there
#  it is an ordinary local USB device, bind-mounted into the container. The
#  flash/debug/hardware-test scripts attach it themselves (usb_attach_probes
#  below) - while attached, Windows tools no longer see it until
#  ./x_usb.sh detach.
#
#  PROBE_SERIAL picks one J-Link when several are attached (./x_usb.sh list
#  shows them); with exactly one it is used automatically.
FLASH_RUNNER="${FLASH_RUNNER:-jlink}"
PROBE_SERIAL="${PROBE_SERIAL:-}"
JLINK_USB_VID="1366"                  # SEGGER: every J-Link, incl. the DKs' J-Link OB
USBIPD_EXE="${USBIPD_EXE:-/mnt/c/Program Files/usbipd-win/usbipd.exe}"

# ---------------------------------------------------------------------------
#  Signing
# ---------------------------------------------------------------------------
KEYS_DIR="$FIREFLY_ROOT/keys"
BOOT_KEY_TYPE="ecdsa-p256"            # nRF54L; not RSA as on the i.MX side
BOOT_KEY_FILE="${BOOT_KEY_FILE:-$KEYS_DIR/boot_key.pem}"

#  sysbuild names image directories after the CMake project() name.
APP_IMAGE_NAME="firefly-app"

# ===========================================================================
#  Helpers
# ===========================================================================
c_info()  { printf '\033[36m%s\033[0m\n' "$*"; }
c_ok()    { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn()  { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# Run a command inside the NCS toolchain environment.
#   ncs west build -b "$BOARD_NAME" ...
ncs() {
    c_info "[ncs $NCS_VERSION] $*"
    nrfutil sdk-manager toolchain launch --ncs-version "$NCS_VERSION" -- "$@"
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

usbipd_bin() {
    if command -v usbipd.exe >/dev/null 2>&1; then command -v usbipd.exe
    elif [ -x "$USBIPD_EXE" ];               then echo "$USBIPD_EXE"
    else return 1; fi
}

# J-Links Windows can see, one "<busid> attached|shared|unshared" per line.
# usbipd's STATE column is free text ("Not shared", "Shared (forced)", ...).
usbipd_probes() {
    local bin; bin="$(usbipd_bin)" || return 1
    "$bin" list 2>/dev/null | tr -d '\r' | awk -v vid="$JLINK_USB_VID" '
        /^Persisted/ { exit }
        $1 ~ /^[0-9]+-[0-9]+$/ && tolower($2) ~ ("^" vid ":") {
            state = "shared"
            if ($0 ~ /Not shared[[:space:]]*$/)   state = "unshared"
            else if ($0 ~ /Attached[[:space:]]*$/) state = "attached"
            print $1, state
        }'
}

# USB serial numbers of the J-Links attached to WSL. Reads sysfs, so it works
# the same inside the container. J-Link OB serials carry leading zeros
# ("001057712345") that its own S/N ("1057712345") does not.
attached_probe_serials() {
    local d
    for d in /sys/bus/usb/devices/*; do
        [ "$(cat "$d/idVendor" 2>/dev/null)" = "$JLINK_USB_VID" ] || continue
        sed 's/^0*//' "$d/serial" 2>/dev/null
    done
}

# Device nodes of attached J-Links that this user cannot open yet - udev
# applies 99-firefly-usb.rules a moment after the device appears.
probe_nodes_pending() {
    local d node
    for d in /sys/bus/usb/devices/*; do
        [ "$(cat "$d/idVendor" 2>/dev/null)" = "$JLINK_USB_VID" ] || continue
        node="$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$d/busnum")" "$(cat "$d/devnum")")"
        [ -w "$node" ] || echo "$node"
    done
}

# Attach every J-Link Windows can see to WSL. Runs in WSL, never in the
# container: usbipd.exe is reached through WSL's Windows interop.
usb_attach_probes() {
    local bin line busid state changed=0 wanted=0 i
    bin="$(usbipd_bin)" || { c_err "!!! usbipd-win is not installed - run ./x_usb.sh setup"; return 1; }
    [ -d /dev/bus/usb ] || { c_err "!!! USB/IP is not set up in WSL - run ./x_usb.sh setup"; return 1; }

    while read -r busid state; do
        [ -n "$busid" ] || continue
        wanted=$((wanted + 1))
        case "$state" in
            attached) continue ;;
            unshared)
                # Sharing a device is a one-time, admin-only step per USB port.
                c_warn "J-Link on Windows USB bus $busid is not shared yet - approve the"
                c_warn "Windows admin prompt to share it (once per DK/USB port)."
                powershell.exe -NoProfile -Command \
                    "Start-Process -Verb RunAs -Wait -WindowStyle Hidden -FilePath '$(wslpath -w "$bin")' -ArgumentList 'bind','--busid','$busid'" \
                    || { c_err "!!! Sharing bus $busid was declined or failed."; return 1; }
                ;;
        esac
        c_info "Attaching J-Link on Windows USB bus $busid to WSL..."
        "$bin" attach --wsl --busid "$busid" || {
            c_err "!!! usbipd could not attach bus $busid. Close any Windows program using"
            c_err "    the J-Link (nRF Connect for Desktop, J-Link Commander, a serial terminal)."
            return 1
        }
        changed=1
    done < <(usbipd_probes)

    if [ "$wanted" -eq 0 ]; then
        c_err "!!! Windows sees no J-Link. Is the DK plugged in and switched on?"
        return 1
    fi
    [ "$changed" = 1 ] || return 0

    for i in $(seq 1 50); do
        if [ "$(attached_probe_serials | wc -l)" -ge "$wanted" ] && [ -z "$(probe_nodes_pending)" ]; then
            return 0
        fi
        sleep 0.2
    done
    c_err "!!! J-Link attached but not usable in WSL after 10 s: $(probe_nodes_pending)"
    c_err "    Missing udev rule? Run ./x_usb.sh setup"
    return 1
}

# The DKs' serial consoles. The script containers get them as /dev/ttyACM*;
# the VS Code dev container mounts WSL's /dev at /dev/host instead, so a DK
# attached after it started still shows up there.
serial_ports() {
    local dev
    for dev in /dev/ttyACM* /dev/host/ttyACM*; do
        [ -e "$dev" ] && echo "$dev"
    done
    return 0
}

# Sets PROBE_ARGS to west's runner arguments for the J-Link to use.
select_probe() {
    local serials
    mapfile -t serials < <(attached_probe_serials)
    if [ "${#serials[@]}" -eq 0 ]; then
        c_err "!!! No J-Link is attached to WSL. From a WSL terminal (not the"
        c_err "    container): ./x_usb.sh attach"
        return 1
    fi
    if [ -n "$PROBE_SERIAL" ]; then
        PROBE_ARGS=(--dev-id "$PROBE_SERIAL")
    elif [ "${#serials[@]}" -gt 1 ]; then
        c_err "!!! ${#serials[@]} J-Links attached (${serials[*]}) - pick one:"
        c_err "    PROBE_SERIAL=<serial> $0"
        return 1
    else
        PROBE_ARGS=(--dev-id "${serials[0]}")
    fi
    c_info "J-Link ${PROBE_ARGS[1]}"
}

# ===========================================================================
#  Container dispatch
# ===========================================================================

# Fingerprint of everything that goes into the image. Stamped on it as a label
# at build time; a mismatch means docker/Dockerfile or a pin changed since.
firefly_image_hash() {
    {
        # Comments and blank lines do not change the image - editing them
        # must not cost everyone a rebuild.
        grep -vE '^[[:space:]]*(#|$)' "$FIREFLY_ROOT/docker/Dockerfile"
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
#   --network host     the container shares WSL's network
#   /dev/bus/usb +
#   cgroup rules       J-Links attached by usbipd (major 189) and their
#                      CDC-ACM consoles (major 166), even ones re-enumerated
#                      while the container runs
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

    # Flash/debug/hardware-test scripts set FIREFLY_USB=1: attach the probe
    # here in WSL, where usbipd.exe is reachable, before entering the container.
    if [ "${FIREFLY_USB:-0}" = 1 ]; then
        usb_attach_probes || exit 1
    fi
    local usb=() dev
    if [ -d /dev/bus/usb ]; then
        usb+=(-v /dev/bus/usb:/dev/bus/usb --device-cgroup-rule "c 189:* rmw")
    fi
    for dev in /dev/ttyACM*; do
        [ -e "$dev" ] && usb+=(--device "$dev")
    done
    [ "${#usb[@]}" -eq 0 ] || usb+=(--device-cgroup-rule "c 166:* rmw")

    local tty=(-i) envs=() v p
    [ -t 0 ] && [ -t 1 ] && tty=(-it)
    # Only what the caller exported (e.g. PROBE_SERIAL) - not the
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
        --cap-add SYS_PTRACE --security-opt seccomp=unconfined "${usb[@]}" \
        -v "$FIREFLY_ROOT:$FIREFLY_CONTAINER_ROOT" -w "$wd" \
        "${envs[@]}" "$FIREFLY_IMAGE" "$@"
}

# A numbered script sourcing this from a WSL shell re-runs itself in the
# container. "$0"/"$@" are the sourcing script's own name and arguments.
# 0_docker.sh sets FIREFLY_HOST_ONLY - it is what builds the container.
if [ -z "${FIREFLY_CONTAINER:-}" ] && [ "${FIREFLY_HOST_ONLY:-0}" != 1 ]; then
    __script="$(firefly_container_path "$(realpath "$0")")" || {
        c_err "!!! $0 is not inside $FIREFLY_ROOT"; exit 1; }
    firefly_docker_exec "$__script" "$@"
fi
