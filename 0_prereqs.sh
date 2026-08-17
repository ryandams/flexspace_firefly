#!/usr/bin/env bash
# ===========================================================================
#  0. WSL2 host prerequisites
# ===========================================================================
#  Safe to re-run.
#
#  The NCS toolchain bundle (step 1) provides the Zephyr SDK, CMake, ninja,
#  gperf, dtc, Python and west. The apt packages below are the things it does
#  NOT provide:
#
#    gcc-multilib / g++-multilib  native_sim compiles with the HOST compiler
#                                 and builds 32-bit by default
#    git, curl, file, xz-utils    used by west and the toolchain installer
#    libxcb-*, libxkbcommon-x11-0,
#    libsm6, libice6               JLinkExe (see the flashing note below)
#                                 depends on these for its GUI tools even
#                                 though ./4_flash.sh only needs the CLI.
#                                 `sudo dpkg -i JLink_Linux_*.deb` fails to
#                                 configure without them on a minimal WSL2
#                                 Ubuntu image - installing them up front
#                                 here means that just works.
#    gdb                          native host debugger for native_sim builds
#                                 (no target hardware, no J-Link - see
#                                 launch.json's "native_sim" configuration)
#    ripgrep                      scripts/check_thread_registry.sh and
#                                 scripts/static_analysis.sh shell out to `rg`
#    gcovr                        ./7_test.sh coverage and the CI "Coverage
#                                 gate" step render the twister coverage report
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"

c_info "Installing apt prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    build-essential gcc-multilib g++-multilib \
    git curl wget file xz-utils unzip \
    python3 python3-pip python3-venv \
    device-tree-compiler \
    libxcb-render-util0 libxcb-shape0 libxcb-icccm4 libxcb-keysyms1 \
    libxcb-image0 libxkbcommon-x11-0 libsm6 libice6 \
    gdb ripgrep gcovr

# ---------------------------------------------------------------------------
#  nRF Util - a single binary, not an apt package
# ---------------------------------------------------------------------------
mkdir -p "$NRFUTIL_DIR"

if [ ! -x "$NRFUTIL" ]; then
    c_info "Downloading nRF Util -> $NRFUTIL"
    curl -fsSL "$NRFUTIL_URL" -o "$NRFUTIL"
    chmod +x "$NRFUTIL"
else
    c_ok "nRF Util already present: $NRFUTIL"
fi

# Put nrfutil on PATH persistently. The scripts do not depend on this - they
# fall back to the absolute path - but an interactive `nrfutil ...` should work.
case ":$PATH:" in
    *":$NRFUTIL_DIR:"*) c_ok "$NRFUTIL_DIR already on PATH" ;;
    *)
        if [ -f "$HOME/.bashrc" ] && grep -qF "$NRFUTIL_DIR" "$HOME/.bashrc"; then
            c_warn "$NRFUTIL_DIR is in ~/.bashrc but not this shell - open a new one."
        else
            c_info "Adding $NRFUTIL_DIR to PATH in ~/.bashrc"
            {
                echo ""
                echo "# added by firefly 0_prereqs.sh"
                echo "export PATH=\"\$PATH:$NRFUTIL_DIR\""
            } >> "$HOME/.bashrc"
            c_warn "Open a new shell (or: source ~/.bashrc) to pick it up."
        fi
        export PATH="$PATH:$NRFUTIL_DIR"
        ;;
esac

"$NRFUTIL" self-upgrade || true
for cmd in "${NRFUTIL_COMMANDS[@]}"; do
    c_info "Installing / upgrading nRF Util command: $cmd"
    "$NRFUTIL" install "$cmd" || true
done
"$NRFUTIL" --version

# ---------------------------------------------------------------------------
#  Where does this workspace live?
# ---------------------------------------------------------------------------
case "$FIREFLY_ROOT" in
    /mnt/*)
        c_warn ""
        c_warn "!!! This workspace is on $FIREFLY_ROOT (a Windows drive)."
        c_warn "    Building Zephyr from /mnt/c under WSL2 is SLOWER than building"
        c_warn "    on Windows - you get the worst of both. Move it into the WSL"
        c_warn "    filesystem:"
        c_warn "        cp -r \"$FIREFLY_ROOT\" ~/firefly && cd ~/firefly"
        ;;
    *)  c_ok "Workspace is in the WSL filesystem - good." ;;
esac

# ---------------------------------------------------------------------------
#  Flashing note
# ---------------------------------------------------------------------------
#  `west flash -r jlink` always shells out to a local JLinkExe binary, even
#  when it is only being pointed at a remote server over --dev-id <ip>.
#  Having JLinkRemoteServer.exe on Windows is NOT enough - JLinkExe (the
#  Linux J-Link client) has to be installed in WSL2 too.
if ! command -v JLinkExe >/dev/null 2>&1; then
    c_warn ""
    c_warn "!!! JLinkExe not found - ./4_flash.sh will fail with"
    c_warn "    'required program JLinkExe not found' until this is installed:"
    c_warn "      1. Download the 64-bit DEB installer from"
    c_warn "         https://www.segger.com/downloads/jlink/#J-LinkSoftwareAndDocumentationPack"
    c_warn "         (EULA-gated, so this has to be done from a browser - WSL2's"
    c_warn "         Firefox works if you don't have one on the Windows side handy)"
    c_warn "      2. sudo dpkg -i JLink_Linux_V*_x86_64.deb"
    c_warn "    This installs the Linux J-Link *client* - it talks to the"
    c_warn "    JLinkRemoteServer.exe running on Windows over TCP, it does not"
    c_warn "    replace it."
fi

# ---------------------------------------------------------------------------
#  VS Code debugging
# ---------------------------------------------------------------------------
#  nRF Connect for VS Code's own debug flow depends on its *bundled*
#  nrfutil-device for device enumeration (separate from, and not
#  redirectable to, the system nrfutil above) - this has repeatedly lagged
#  behind what a moving nrf/zephyr source pin requires. cortex-debug talks
#  directly to JLinkGDBServer instead - same binary the flashing note below
#  already requires - so it sidesteps that version-skew entirely.
if command -v code >/dev/null 2>&1; then
    c_info "Installing cortex-debug VS Code extension..."
    code --install-extension marus25.cortex-debug
else
    c_warn "code CLI not found - install the 'cortex-debug' extension manually if" \
        "nRF Connect for VS Code's own debugger hits a nrfutil-device version mismatch."
fi

cat <<'NOTE'

Flashing from WSL2
------------------
WSL2 has no native USB, so the DK's debug probe is not visible here.
Rather than usbipd, run the J-Link remote server on WINDOWS:

    JLinkRemoteServer.exe        (from the SEGGER J-Link install)

then flash from here with ./4_flash.sh, which connects over TCP. This also
needs JLinkExe installed locally in WSL2 - see the warning above if missing.

NOTE
c_ok "Prerequisites done. Next: ./1_toolchain.sh"
