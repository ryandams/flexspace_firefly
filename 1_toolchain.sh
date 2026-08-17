#!/usr/bin/env bash
# ===========================================================================
#  1. nRF Connect SDK toolchain
# ===========================================================================
#  Nordic ships a per-release toolchain bundle containing the matching Zephyr
#  SDK plus CMake, ninja, gperf, dtc, Git, Python (with west and every
#  requirements.txt) and nRF Util. Version-managed by `nrfutil sdk-manager`,
#  so several NCS versions coexist.
# ===========================================================================
set -euo pipefail
source "$(dirname "$0")/variables.sh"

bin="$(nrfutil_bin)" || { c_err "!!! nrfutil not found - run ./0_prereqs.sh"; exit 1; }

c_info "Installing / updating nRF Util sdk-manager..."
"$bin" install sdk-manager || true

c_info ""
c_info "Available nRF Connect SDK versions (newest first):"
head_of 15 "$bin" sdk-manager search

latest="$(ncs_latest_stable || true)"
if [ -n "$latest" ]; then
    if [ "$latest" = "$NCS_VERSION" ]; then
        c_ok "  $NCS_VERSION is the newest stable release."
    else
        c_warn "  Newest stable is $latest (you have NCS_VERSION=$NCS_VERSION)."
        c_warn "  Change it in variables.sh if you want it. Pinning an older"
        c_warn "  version on purpose is fine - drifting onto one is not."
    fi
fi

# nRF54LM20 support landed in v3.2.0
minor="$(echo "$NCS_VERSION" | sed -E 's/^v([0-9]+)\.([0-9]+).*/\1\2/')"
if [ "${minor:-0}" -lt 32 ] 2>/dev/null; then
    c_err "!!! $NCS_VERSION predates nRF54LM20 support (needs v3.2.0+). Aborting."
    exit 1
fi

c_info ""
c_info "Installing toolchain for $NCS_VERSION ..."
"$bin" sdk-manager toolchain install --ncs-version "$NCS_VERSION"

c_info ""
c_info "Verifying toolchain environment..."
# Advisory only - a failure here must never abort the install that just
# succeeded, and the output must not be piped (see head_of in variables.sh).
ncs west --version || c_warn "  west did not respond"
head_of 1 ncs arm-zephyr-eabi-gcc --version

c_ok ""
c_ok "Toolchain ready. Next: ./2_workspace.sh"
