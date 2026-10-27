# firefly Zephyr workspace

Firefly is an nRF Connect SDK application for the nRF54LM20 DK and the
nRF93M1 DK, with deterministic `native_sim` tests. The
manifest temporarily pins sdk-nrf main at commit `e8b176a4900a560d180112302fc5b48dde19bf70`
for nRF93M1 modem support. That manifest selects sdk-zephyr
`0e25e66118d903037be2350cccc382134b7e62ad`. The latest available Nordic
toolchain remains pinned to v3.4.0 until an aligned stable release is published.

Generated application builds live under `ncsworkspace/builds/`; Twister output
lives separately under `ncsworkspace/test-results/`.

## Setup

The build environment is a Docker image (`firefly-dev`), so every developer
compiles with the same toolchain, nrfutil and J-Link versions - all pinned in
`variables.sh`. Docker Engine runs inside WSL2 itself; Docker Desktop is not
used. Keep the repo on the Linux filesystem (`~/firefly`, not `/mnt/c`); it is
bind-mounted into the container, so sources and builds stay on ext4.

```bash
./0_docker.sh install    # once per machine: Docker Engine (sudo), then reopen WSL
./0_docker.sh build      # ~10 min: the image, with the NCS toolchain baked in
./x_usb.sh setup         # once per machine: usbipd-win (admin prompt) + WSL USB (sudo)
./2_workspace.sh         # west init/update - clones several GB
```

`0_docker.sh build` needs the J-Link `.deb` (`JLINK_VERSION` in
`variables.sh`). SEGGER's EULA blocks scripted downloads, so get it from
segger.com in a browser; the script picks it up from your Windows Downloads
folder.

From then on, run the numbered scripts from WSL exactly as before. Each one
re-launches itself in a throwaway container with the repo mounted at
`/workspaces/firefly`, the same path for everyone. If `docker/Dockerfile` or
a pin has changed since your image was built, the next script rebuilds the
image first. `./0_docker.sh shell` opens an interactive shell in the container.

**VS Code:** open the folder and choose *Reopen in Container*
(`.devcontainer/`). The dev container uses the same image and mount as the
scripts, so builds from either are interchangeable. `launch.json` and the
clangd paths assume you are inside it. Commit and push from WSL or from the
dev container, which forwards your git credentials; the plain script containers
have no git credentials.

**Flashing and debugging** use the DK's on-board J-Link over USB.
[usbipd-win](https://github.com/dorssel/usbipd-win) passes it from Windows to
WSL, and from there into the container. `./4_flash.sh`, `./5_debug.sh` and
`./7_test.sh test-hardware` attach it themselves. The first time a DK (or
USB port) is used, Windows asks for admin approval to share it. While
attached, the DK and its COM port are gone from Windows; they show up in WSL
as a USB device and `/dev/ttyACM*` instead. `./x_usb.sh detach` gives them
back; `./x_usb.sh list` shows what is where. Replugging or power-cycling the
DK drops the attachment; the next flash re-attaches. In the VS Code dev
container, which cannot reach usbipd, run `./x_usb.sh attach` in a WSL
terminal first (it also runs when the container opens). With several DKs
attached, pick one with `PROBE_SERIAL=<serial>`.

**Serial console:** while the DK is attached to WSL, its COM ports exist only
in WSL, so a Web Serial log viewer has to run in a Linux browser here.
`./x_serial.sh install` (once) installs Google Chrome from Google's .deb
(Ubuntu's Chromium is a snap, which cannot open serial ports). After that,
`./x_serial.sh` attaches the DK and opens the project's
[log_viewer.html](log_viewer.html) as a Chrome app window (set
`SERIAL_VIEWER_HTML` for another viewer). The window shows on the Windows
desktop through WSLg and can stay connected while `./4_flash.sh` flashes.

### Changing toolchain versions

Edit the pins in `variables.sh` (`NCS_VERSION`, `NCS_TOOLCHAIN_BUNDLE_ID`,
`NRFUTIL_*`, `JLINK_VERSION`) and commit. Everyone's image rebuilds on their
next script run. The bundle ID for a version is shown by
`nrfutil sdk-manager toolchain list` after installing it once.

## Build and test modes

```bash
./3_build.sh app-target -p       # unsigned development target image
./4_flash.sh                     # flash over USB (usbipd-win)
./5_debug.sh                     # interactive target debugging
./6_menuconfig.sh                # configure an existing build
./7_test.sh                      # all automated tests + combined report
./8_format.sh check              # verify C/C++ formatting
./8_format.sh apply              # format C/C++ sources and tests
./7_test.sh test-native          # optional: run only native tests
./7_test.sh test-target-build    # compile portable suites for the DK
./7_test.sh test-hardware        # execute DK-only tests (connected board)
./7_test.sh sanitizer            # ASan + UBSan portable suites
./7_test.sh coverage             # HTML report, 90% line/70% branch gate
```

Release builds require a private signing key. Run `./x_keygen.sh`, protect the
result, then use `./3_build.sh release -p`. Release mode alone enables MCUboot,
production configuration, signing, MCUboot, and a DFU package. The ordinary target
build does not claim to be signed.

## Board and modem

The target hardware is chosen in `firefly-app/prj.conf`, one board and one
modem:

```
CONFIG_FIREFLY_TARGET_BOARD_NRF93M1DK=y
CONFIG_FIREFLY_TARGET_MODEM_NRF93M1=y
```

| Board | Modems |
|---|---|
| `NRF93M1DK` | `NRF93M1` (on board) |
| `NRF54LM20DK` | `NONE`, `EG800Z`, `LE270` (both uart21), `NRF93M1_EXT` (uart30) |

`3_build.sh` passes the board to `west build -b`; the app's `CMakeLists.txt`
adds the modem's `conf/modem_<x>.conf` + `boards/<x>.overlay`, and stops the
build if the pair is invalid or doesn't match the board being built (for
example from VS Code's nRF Connect extension). Flash, debug and the target
test stages use the same selection. There is one build directory,
`ncsworkspace/builds/build`; after changing the selection, `./3_build.sh`
rebuilds it. See `firefly-app/README.md` for what each modem configures.

## Test layers

- `tests/thread`: reusable lifecycle contract for `Thread`.
- `tests/service`: portable service behavior, validation, ordering, dependency
  failure injection, and lifecycle tests; runs on native_sim and compiles for
  the DK.
- `tests/gpio`: native-only GPIO emulator pipeline through the real input
  subsystem.
- `tests/hardware`: opt-in tests executed by a board-equipped runner.

Hardware tests are never presented as having run unless `--device-testing`
executes them on a connected DK. Pull requests perform a target compile even
when hardware is unavailable.

## Architecture guarantees

All controller inputs share one copied zbus message channel. A message
subscriber queues payload copies, preserving publication order rather than
reading a channel's latest value. Messages are validated at publication and
dispatch boundaries. Hardware output is behind `firefly_led_port`, allowing
deterministic fault injection without replacing the Zephyr kernel.

`Thread` uses explicit atomic lifecycle states, bounded joins, return codes,
and a stop wake-up hook. State shared with service callers is synchronized.

## Adding a threaded service

A new production class derived from `firefly::Thread` is not accepted until it
is listed in `tests/thread/registry.txt` with an existing behavior test. The
static check runs locally and in CI. Every new threaded service must:

1. Pass the shared lifecycle contract assumptions: duplicate start/stop,
   restart, bounded shutdown, and measured stack margin.
2. Add behavior-specific tests for messages, failures, invalid inputs, and
   shutdown while blocked.
3. Use synchronization rather than fixed sleeps.
4. Check every Zephyr API result and document queue/stack sizing.
5. Compile for native_sim and the target without warnings.

The registry check ensures a new subclass cannot silently land without a test;
it does not pretend a generic lifecycle test proves service-specific behavior.

## CI and quality

Twister scenarios are tagged `portable`, `native`, `integration`, `hardware`,
`contract`, and `service`. CI builds the target app, runs native tests, compiles
portable tests for the target, checks thread registration and API use, and has
an opt-in scheduled hardware job. Coverage excludes upstream Zephyr by setting
the application as its base. ASan/UBSan and LED-port fault injection cover
memory/undefined behavior and mutation-style error paths.

Development enables assertions, stack initialization, stack information,
logging, RTT/SystemView on target, and debug optimization. Production disables
assertions and analyzer/debug settings, lowers logging, optimizes for size, and
is only selected by the signed release build.
