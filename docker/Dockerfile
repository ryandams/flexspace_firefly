# ===========================================================================
#  firefly build environment
# ===========================================================================
#  Everything a developer needs to build, test, flash and debug firefly-app,
#  pinned so every machine gets the same bits. Do not `docker build` this by
#  hand - ./0_docker.sh build passes the pins from variables.sh as build args
#  and stamps the image with a hash the numbered scripts check for staleness.
#
#  The source tree is NOT in the image: the repo (including ncsworkspace/) is
#  bind-mounted at /workspaces/firefly, so checkouts and build output stay on
#  the WSL ext4 filesystem and survive the container.
# ===========================================================================
FROM ubuntu:24.04

ARG NRFUTIL_VERSION
ARG NRFUTIL_SDK_MANAGER_VERSION
ARG NRFUTIL_DEVICE_VERSION
ARG NCS_VERSION
ARG NCS_TOOLCHAIN_BUNDLE_ID
ARG JLINK_VERSION
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    NRFUTIL_HOME=/opt/nrfutil \
    FIREFLY_CONTAINER=1

# The NCS toolchain bundle (below) brings the Zephyr SDK, CMake, ninja,
# gperf, dtc, Python and west. These are what it does NOT bring:
#   gcc-multilib, g++-multilib   native_sim builds 32-bit with the host compiler
#   git, curl, file, xz-utils    used by west and the toolchain installer
#   libxcb-*, libxkbcommon-x11-0,
#   libsm6, libice6              J-Link's package depends on them (GUI tools)
#   gdb                          debugging native_sim builds (launch.json)
#   ripgrep                      scripts/check_thread_registry.sh and
#                                scripts/static_analysis.sh call `rg`
#   gcovr                        ./7_test.sh coverage report
#   ca-certificates, iproute2,
#   sudo                         what a minimal container lacks
#   libusb, libudev              `nrfutil device` and J-Link USB access
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential gcc-multilib g++-multilib \
      git curl file xz-utils ca-certificates \
      libxcb-render-util0 libxcb-shape0 libxcb-icccm4 libxcb-keysyms1 \
      libxcb-image0 libxkbcommon-x11-0 libsm6 libice6 \
      gdb ripgrep gcovr \
      iproute2 sudo less nano bash-completion \
      libusb-1.0-0 libudev1 \
 && rm -rf /var/lib/apt/lists/*

# ---- J-Link -----------------------------------------------------------------
#  EULA-gated download, so ./0_docker.sh copies the .deb into vendor/ first.
#  The package's postinst reloads udev rules, which fails without a running
#  udevd. Not needed: the container never sees a device being added - USB
#  nodes come in already permission-fixed by WSL's udev (see x_usb.sh). Unpack,
#  drop the postinst, then let
#  apt resolve its dependencies and finish configuring it.
COPY vendor/JLink_Linux_${JLINK_VERSION}_x86_64.deb /tmp/jlink.deb
RUN apt-get update \
 && dpkg --unpack /tmp/jlink.deb \
 && rm -f /var/lib/dpkg/info/jlink.postinst \
 && apt-get install -y -f --no-install-recommends \
 && dpkg --configure -a \
 && rm -rf /var/lib/apt/lists/* /tmp/jlink.deb \
 && command -v JLinkExe

# ---- user -------------------------------------------------------------------
#  UID/GID match the host user, so files written into the bind mount are owned
#  by you, not root. ubuntu:24.04 ships an `ubuntu` user on 1000 - remove it.
#  Created before the toolchain install so the toolchain is written as this
#  user directly - a `chown -R` afterwards would copy all 5 GB into a new layer.
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd -o -g "${USER_GID}" "${USERNAME}" \
 && useradd -m -o -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USERNAME}" \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
 && chmod 0440 "/etc/sudoers.d/${USERNAME}" \
 && install -d -o "${USER_UID}" -g "${USER_GID}" /opt/nrfutil /opt/ncs \
 && install -o "${USER_UID}" -g "${USER_GID}" /dev/null /usr/local/bin/nrfutil

USER ${USERNAME}

# ---- nRF Util + NCS toolchain -------------------------------------------------
#  The bootstrap URL always serves the latest nrfutil, so pin it down with
#  self-upgrade. The toolchain is pinned by bundle ID, not just NCS version:
#  `--ncs-version` alone takes the newest (possibly patched) bundle for that
#  release, which would let two images built a week apart diverge.
RUN curl -fsSL -o /usr/local/bin/nrfutil \
      https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil \
 && chmod +x /usr/local/bin/nrfutil \
 && nrfutil self-upgrade --to-version "${NRFUTIL_VERSION}" \
 && nrfutil install "sdk-manager=${NRFUTIL_SDK_MANAGER_VERSION}" "device=${NRFUTIL_DEVICE_VERSION}" \
 && nrfutil sdk-manager config install-dir set /opt/ncs \
 && nrfutil sdk-manager toolchain install \
      --toolchain-bundle-id "${NCS_TOOLCHAIN_BUNDLE_ID}" \
      --for-ncs-version "${NCS_VERSION}" \
      --skip-cmake-registration \
 && ln -s "/opt/ncs/toolchains/${NCS_TOOLCHAIN_BUNDLE_ID}" /opt/ncs/toolchain \
 && rm -rf /opt/ncs/downloads /opt/ncs/tmp "${NRFUTIL_HOME}/logs" \
 && nrfutil --version && nrfutil list

WORKDIR /workspaces/firefly
CMD ["bash"]
