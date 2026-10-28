#!/usr/bin/env bash
# Default: run every automated, non-hardware test and write test-results/report.md.
# Individual modes: static, test-native, test-target-build, test-hardware,
# coverage, sanitizer. A suite (a directory under firefly-app/tests) may follow
# a twister mode: ./7_test.sh test-hardware nrf93m1_power
# ./7_test.sh clean       wipe test-results/ entirely
#                         (twister renames each run's old output dir aside as
#                         .1, .2, ... instead of overwriting it, so this
#                         directory only ever grows until you clean it)
set -euo pipefail
# The hardware stage needs the DK's J-Link and serial console in the container.
[ "${1:-}" = test-hardware ] && FIREFLY_USB=1
source "$(dirname "$0")/variables.sh"
mode="${1:-all}"
suite="${2:-}"
usage="usage: $0 [all|static|test-native|test-target-build|test-hardware|coverage|sanitizer|clean] [suite]"

if [ "$mode" = clean ]; then
    [ -z "$suite" ] || { c_err "clean takes no suite argument"; exit 2; }
    results_root="$WORKSPACE_DIR/test-results"
    rm -rf "$results_root"
    c_ok "Cleaned $results_root"
    exit 0
fi

require_workspace

if [ "$mode" = all ]; then
    [ -z "$suite" ] || { c_err "A suite cannot be selected in all mode"; exit 2; }
    report="$WORKSPACE_DIR/test-results/report.md"
    mkdir -p "$(dirname "$report")"
    modes=(static test-native test-target-build sanitizer coverage)
    failed=0
    {
        echo "# Firefly automated test report"
        echo
        echo "Generated: $(date --iso-8601=seconds)"
        echo
        echo "| Test stage | Result | Detailed report |"
        echo "|---|---:|---|"
    } > "$report"
    for test_mode in "${modes[@]}"; do
        if "$0" "$test_mode"; then
            result="PASS"
        else
            result="FAIL"
            failed=1
        fi
        if [ "$test_mode" = static ]; then
            details="console output"
        else
            details="[$test_mode/twister.xml]($test_mode/twister.xml)"
        fi
        printf '| `%s` | **%s** | %s |\n' "$test_mode" "$result" "$details" >> "$report"
    done
    {
        echo
        echo "Hardware tests are excluded because they require a connected serial console."
        echo "Run \`./7_test.sh test-hardware\` explicitly when one is available."
    } >> "$report"
    if [ "$failed" -ne 0 ]; then
        c_err "Automated tests failed. Report: $report"
        exit 1
    fi
    c_ok "All automated tests passed. Report: $report"
    exit 0
fi

case "$mode" in
    static|test-native|test-target-build|test-hardware|coverage|sanitizer) ;;
    *) c_err "$usage"; exit 2 ;;
esac

# Thread registry and checked-zbus-publish rules (firefly-app/scripts).
if [ "$mode" = static ]; then
    [ -z "$suite" ] || { c_err "static takes no suite argument"; exit 2; }
    "$PROJECT_DIR/scripts/static_analysis.sh"
    c_ok "Static checks passed"
    exit 0
fi

if [ -z "$suite" ]; then
    path="$PROJECT_NAME/tests"
elif [ -d "$PROJECT_DIR/tests/$suite" ]; then
    path="$PROJECT_NAME/tests/$suite"
else
    c_err "unknown suite: $suite (one of: $(ls "$PROJECT_DIR/tests" | tr '\n' ' '))"
    exit 2
fi
cd "$WORKSPACE_DIR"
results_dir="$WORKSPACE_DIR/test-results/$mode"
mkdir -p "$results_dir"
base=(west twister -T "$path" --inline-logs --warnings-as-errors -O "$results_dir")
case "$mode" in
    test-native) ncs "${base[@]}" -p "$SIM_BOARD_NAME" --tag firefly ;;
    test-target-build) require_board; ncs "${base[@]}" -p "$BOARD_NAME" --build-only --tag portable ;;
    test-hardware)
        require_board
        mapfile -t ports < <(serial_ports)
        serial="${DEVICE_SERIAL:-${ports[0]:-}}"
        [ -n "$serial" ] || { c_err "!!! No DK serial port (/dev/ttyACM*) - is the DK attached?"; exit 1; }
        ncs "${base[@]}" -p "$BOARD_NAME" --device-testing \
            --device-serial "$serial" --tag hardware ;;
    coverage)
        ncs "${base[@]}" -p "$SIM_BOARD_NAME" --tag firefly --coverage \
            --coverage-basedir "$PROJECT_DIR" --coverage-tool gcovr
        report="$results_dir/coverage/index.html"
        lines="$(awk '/Lines:<\/th>/{getline; gsub(/<[^>]*>|%| /, ""); print; exit}' "$report")"
        branches="$(awk '/Branches:<\/th>/{getline; gsub(/<[^>]*>|%| /, ""); print; exit}' "$report")"
        awk -v value="$lines" 'BEGIN { exit !(value >= 90) }' || { c_err "line coverage $lines% < 90%"; exit 1; }
        awk -v value="$branches" 'BEGIN { exit !(value >= 70) }' || { c_err "branch coverage $branches% < 70%"; exit 1; }
        c_ok "coverage gate passed: lines $lines%, branches $branches%" ;;
    sanitizer)
        ncs "${base[@]}" -p "$SIM_BOARD_NAME" --tag portable \
            --extra-args=EXTRA_CONF_FILE=asan.conf ;;
esac
