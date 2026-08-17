#!/usr/bin/env bash
# ===========================================================================
#  Install firefly into the WSL2 filesystem
# ===========================================================================
#  Run this ONCE, from inside WSL2:
#
#      bash /mnt/c/zephyrspace/firefly/install_to_wsl.sh
#
#  It copies the scripts and the app repo to ~/firefly. It deliberately does
#  NOT copy any west checkouts - `./2_workspace.sh` clones those fresh into
#  the Linux filesystem, which is the whole point of moving.
#
#  Why not just work from /mnt/c: building Zephyr across the 9p mount is
#  slower than building on Windows. You would get the worst of both.
# ===========================================================================
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/firefly}"

# /proc/version says "Microsoft" on WSL1 too, so check properly.
# WSL2: uname -r contains "microsoft-standard-WSL2"
# WSL1: uname -r ends "-Microsoft", no real kernel - west/native_sim unsupported
case "$(uname -r)" in
    *WSL2*|*wsl2*|*microsoft-standard*) ;;
    *)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            echo "!!! This is WSL1, not WSL2 (uname -r = $(uname -r))." >&2
            echo "    WSL1 has no real Linux kernel; native_sim and west are not" >&2
            echo "    supported. Convert this distro from a Windows PowerShell:" >&2
            echo "        wsl --set-version <DistroName> 2" >&2
            echo "        wsl --set-default-version 2" >&2
        else
            echo "!!! Not running under WSL. Run this from inside your WSL2 shell." >&2
        fi
        exit 1
        ;;
esac

case "$SRC" in
    /mnt/*) ;;
    *) echo "!!! Source is $SRC, not a Windows drive - already installed?" >&2; exit 1 ;;
esac

echo "source:      $SRC"
echo "destination: $DEST"
echo

if [ -e "$DEST" ]; then
    echo "!!! $DEST already exists."
    read -r -p "    Overwrite scripts and $DEST/ncsworkspace/firefly-app? [y/N] " a
    [ "$a" = "y" ] || { echo "Aborted."; exit 0; }
fi

mkdir -p "$DEST/ncsworkspace"

echo "Copying scripts..."
cp "$SRC"/*.sh "$DEST"/
cp "$SRC"/README.md "$DEST"/ 2>/dev/null || true
chmod +x "$DEST"/*.sh

echo "Copying app repo..."
rm -rf "$DEST/ncsworkspace/firefly-app"
cp -r "$SRC/ncsworkspace/firefly-app" "$DEST/ncsworkspace/firefly-app"

# Windows checkouts and CMake caches must not come across.
rm -rf "$DEST/ncsworkspace/firefly-app/.git" \
       "$DEST/ncsworkspace/firefly-app/build" \
       "$DEST/ncsworkspace/firefly-app/twister-out"*

# CRLF would break shebangs and Kconfig parsing.
if command -v dos2unix >/dev/null 2>&1; then
    find "$DEST" -type f \( -name '*.sh' -o -name '*.conf' -o -name '*.yml' \
         -o -name '*.yaml' -o -name 'Kconfig*' -o -name 'CMakeLists.txt' \
         -o -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \) \
         -exec dos2unix -q {} +
else
    find "$DEST" -type f \( -name '*.sh' -o -name '*.conf' -o -name '*.yml' \
         -o -name '*.yaml' -o -name 'Kconfig*' -o -name 'CMakeLists.txt' \
         -o -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \) \
         -exec sed -i 's/\r$//' {} +
fi

cat <<NEXT

Installed to $DEST

Next:
    cd $DEST
    ./0_prereqs.sh        apt packages + nRF Util
    ./1_toolchain.sh      NCS toolchain bundle
    ./2_workspace.sh      west init -l firefly-app + update   (clones several GB)
    ./7_test.sh           all automated tests + combined report
    ./3_build.sh          build for the DK
    ./12_format.sh check  verify C/C++ formatting

The Windows copy under C:\\zephyrspace can be deleted once this works.
NEXT
