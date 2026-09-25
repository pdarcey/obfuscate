#!/bin/bash
#
# test-all.sh
#
# Runs every test suite, and exits non-zero if any of them fails:
#   1. Unit tests (Swift Testing) for ObfuscateKit    swift test
#   2. End-to-end tests of the obfuscate binary        Scripts/test-obfuscate.sh
#   3. Tests of the install scripts                    Scripts/test-install-scripts.sh
#
#     Scripts/test-all.sh
#
# Build the project first: the end-to-end tests use the obfuscate on your PATH
# (or OBFUSCATE=/path/to/obfuscate).
#
# © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

set -u

SRCROOT=$(cd "$(dirname "$0")/.." && pwd)
LOGS=$(mktemp -d)
trap 'rm -rf "$LOGS"' EXIT

FAILED_SUITES=()

# run_suite <name> <command...>: runs a suite, showing only its summary unless it fails.
run_suite() {
    local name=$1
    shift
    local log="$LOGS/$name.log"

    printf '%-24s' "$name"
    if (cd "$SRCROOT" && "$@") > "$log" 2>&1; then
        echo "✅ $(summary "$log")"
    else
        echo "❌ $(summary "$log")"
        FAILED_SUITES+=("$name")
        # Show what failed, without the passing noise.
        grep -E "❌|✘|error:|failed|Expectation" "$log" | head -40 | sed 's/^/    /'
    fi
}

# summary <log>: the suite's own one-line result, if it printed one.
summary() {
    grep -E "^[0-9]+ passed, [0-9]+ failed$|Test run with .* (passed|failed)" "$1" | tail -1 | sed -E 's/^[^A-Za-z0-9]+//'
}

run_suite "Unit tests" bash -c 'cd ObfuscateKit && swift test'
run_suite "End-to-end tests" Scripts/test-obfuscate.sh
run_suite "Install-script tests" Scripts/test-install-scripts.sh

echo
if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
    echo "All test suites passed."
else
    echo "Failed: ${FAILED_SUITES[*]}"
    exit 1
fi
