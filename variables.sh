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
