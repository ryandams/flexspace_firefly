# firefly Zephyr workspace

Firefly is an nRF Connect SDK application for
`nrf54lm20dk/nrf54lm20a/cpuapp`, with deterministic `native_sim` tests. The
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

**Flashing and debugging** work as before: the container shares WSL's network,
so it reaches `JLinkRemoteServer.exe` on Windows the same way.

The first build after moving to the container needs `-p`: CMake caches from
raw WSL hold the old paths.

To run on raw WSL without the container, set up with
`FIREFLY_NATIVE=1 ./0_prereqs.sh && FIREFLY_NATIVE=1 ./1_toolchain.sh` and
prefix every script with `FIREFLY_NATIVE=1`.

### Changing toolchain versions

Edit the pins in `variables.sh` (`NCS_VERSION`, `NCS_TOOLCHAIN_BUNDLE_ID`,
`NRFUTIL_*`, `JLINK_VERSION`) and commit. Everyone's image rebuilds on their
next script run. The bundle ID for a version is shown by
`nrfutil sdk-manager toolchain list` after installing it once.

## Build and test modes

```bash
./3_build.sh app-target -p       # unsigned development target image
./31_build.sh -p                 # nRF93M1 modem target (on-board, nrf93m1dk)
./32_build.sh -p                 # Quectel EG800Z modem target (external, uart21)
./33_build.sh -p                 # Fibocom LE270 modem target (external, uart21)
./4_flash.sh                     # flash through J-Link Remote Server
./41_flash.sh                    # flash the nRF93M1 target - matches 31_build.sh
./42_flash.sh                    # flash the EG800Z target - matches 32_build.sh
./43_flash.sh                    # flash the LE270 target - matches 33_build.sh
./5_debug.sh                     # interactive target debugging
./51_debug.sh / 52 / 53          # debug the nRF93M1 / EG800Z / LE270 target
./6_menuconfig.sh                # configure an existing build
./7_test.sh                      # all automated tests + combined report
./12_format.sh check             # verify C/C++ formatting
./12_format.sh apply             # format C/C++ sources and tests
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

## Modem targets

`31_build.sh`/`32_build.sh`/`33_build.sh` are thin wrappers around
`3_build.sh` that fix `TARGET` (and, for the two external modems, `MODEM`)
to one of the three modems this project supports - see `variables.sh` for
what each variable selects and `firefly-app/README.md` for the app-side
Kconfig/devicetree behind them. Each gets its own build directory
(`ncsworkspace/builds/build_nrf93m1dk`, `build_eg800z`, `build_le270`), so
switching between them never forces a pristine rebuild of another. Plain
`3_build.sh`/`TARGET=nrf54lm20dk` with no `MODEM` set builds with no modem
at all.

`41/42/43_flash.sh` and `51/52/53_debug.sh` are the matching wrappers for
`4_flash.sh`/`5_debug.sh`. Use them, not the bare `TARGET=... MODEM=...
./4_flash.sh` form: a numbered build script's `export` only lives inside
that script's own process - it does **not** carry over to a separate
`./4_flash.sh` invocation in your shell. Running `./33_build.sh` then
plain `./4_flash.sh` silently flashes the last plain (no-modem) build
instead of `build_le270`, with no error - the two scripts have no way to
know a different target was just built. If you do want the bare form
(e.g. `TARGET=nrf54lm20dk MODEM=le270 ./4_flash.sh`), export the same
`TARGET`/`MODEM` pair to *every* script in the sequence, in the same shell
session.

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
