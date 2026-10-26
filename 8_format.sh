#!/usr/bin/env bash
# Format or verify all owned C and C++ sources using firefly-app/.clang-format.
set -euo pipefail
source "$(dirname "$0")/variables.sh"

mode="${1:-check}"
case "$mode" in
    check|apply) ;;
    *) c_err "Usage: $0 [check|apply]"; exit 2 ;;
esac

mapfile -d '' files < <(
    find "$PROJECT_DIR/code" "$PROJECT_DIR/tests" \
        -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) \
        -print0 | sort -z
)

if ((${#files[@]} == 0)); then
    c_err "No C/C++ source files found"
    exit 1
fi

if [ "$mode" = apply ]; then
    ncs clang-format -i --style=file "${files[@]}"
    c_ok "Formatted ${#files[@]} C/C++ files"
else
    ncs clang-format --dry-run --Werror --style=file "${files[@]}"
    c_ok "Formatting check passed for ${#files[@]} C/C++ files"
fi
