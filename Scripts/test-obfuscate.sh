#!/bin/bash
#
# test-obfuscate.sh
#
# End-to-end tests for the obfuscate binary. Runs it with a set of distinctive
# secrets and checks that:
#   - none of the secrets appear anywhere in the generated file or on stdout
#   - the generated Secrets.swift compiles, and every property decodes back to
#     the original secret
#
#     Scripts/test-obfuscate.sh
#
# Environment:
#   OBFUSCATE  Path to the binary to test. Defaults to `obfuscate` on the PATH
#              (the build installs it to /usr/local/bin).
#
# Exits non-zero if any test fails.
#
# © 2025 Xerodonia Pty Ltd. All rights reserved

set -u

OBFUSCATE=${OBFUSCATE:-$(command -v obfuscate)}
if [ -z "$OBFUSCATE" ] || [ ! -x "$OBFUSCATE" ]; then
    echo "❌ obfuscate binary not found. Build the project, or set OBFUSCATE=/path/to/obfuscate"
    exit 1
fi
echo "Testing $OBFUSCATE"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ✅ $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  ❌ $1"; }

# check <description> <command...>: passes if the command succeeds.
check() {
    local description=$1
    shift
    if "$@"; then pass "$description"; else fail "$description"; fi
}

# Distinctive secrets covering the awkward cases: base64 padding, spaces,
# Unicode, quotes and backslashes, and a leading dash.
SECRETS=(
    "sk-live-4f9a2b7c1d3e5f60"
    "QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
    "has spaces in the middle"
    "ünïcødé-🔑-sécret"
    "quote\"and\\backslash"
    "-leading-dash-secret"
)

echo "Generated file must not contain the secrets"

cd "$WORK" || exit 1
STDOUT=$("$OBFUSCATE" -f Secrets -- "${SECRETS[@]}" 2>&1)
check "exits 0" [ $? -eq 0 ]
check "writes Secrets.swift" [ -f Secrets.swift ]

for secret in "${SECRETS[@]}"; do
    check "file doesn't contain: $secret" sh -c '! grep -qF -- "$1" Secrets.swift' _ "$secret"
    check "stdout doesn't contain: $secret" sh -c '! printf "%s" "$2" | grep -qF -- "$1"' _ "$secret" "$STDOUT"
done

check "one property per secret" \
    [ "$(grep -c 'static var apiKey[0-9]*: String' Secrets.swift)" -eq "${#SECRETS[@]}" ]

echo "Generated file must compile and decode"

# A tiny program that prints each decoded secret on its own line.
{
    for i in $(seq 1 "${#SECRETS[@]}"); do
        echo "print(Secrets.apiKey$i)"
    done
} > main.swift

if swiftc -o decode Secrets.swift main.swift > compile.log 2>&1; then
    pass "Secrets.swift compiles"
    i=0
    while IFS= read -r decoded; do
        check "apiKey$((i + 1)) decodes to the original secret" [ "$decoded" = "${SECRETS[$i]}" ]
        i=$((i + 1))
    done < <(./decode)
    check "decodes every secret" [ "$i" -eq "${#SECRETS[@]}" ]
else
    fail "Secrets.swift compiles"
    sed 's/^/      /' compile.log
fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
