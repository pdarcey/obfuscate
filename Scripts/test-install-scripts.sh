#!/bin/sh
#
# test-install-scripts.sh
#
# Tests install-binary.sh and install-man-page.sh against temporary folders,
# so nothing is written to /usr/local.
#
#     Scripts/test-install-scripts.sh
#
# Exits non-zero if any test fails.
#
# © 2025 Xerodonia Pty Ltd. All rights reserved

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRCROOT=$(dirname "$SCRIPT_DIR")
WORK=$(mktemp -d)
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  ✅ $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  ❌ $1"; }

# check <description> <command...>: passes if the command succeeds.
check() {
    description=$1
    shift
    if "$@"; then pass "$description"; else fail "$description"; fi
}

# The "unwritable" tests are meaningless as root, because root can write anywhere.
IS_ROOT=false
[ "$(id -u)" -eq 0 ] && IS_ROOT=true

echo "install-man-page.sh"

# Normal install
DEST="$WORK/man/man1"
OUT=$(SRCROOT="$SRCROOT" MAN_DEST_DIR="$DEST" "$SCRIPT_DIR/install-man-page.sh" 2>&1)
check "exits 0 on a normal install" [ $? -eq 0 ]
check "creates obfuscate.1.gz" [ -f "$DEST/obfuscate.1.gz" ]
check "gzipped page matches the source" \
    sh -c 'gzip -dc "$1" | cmp -s - "$2"' _ "$DEST/obfuscate.1.gz" "$SRCROOT/obfuscate/obfuscate.1"
check "leaves no temporary files" [ "$(ls "$DEST")" = "obfuscate.1.gz" ]

# Reinstall over an existing page, with a stale uncompressed copy present
touch "$DEST/obfuscate.1"
SRCROOT="$SRCROOT" MAN_DEST_DIR="$DEST" "$SCRIPT_DIR/install-man-page.sh" > /dev/null 2>&1
check "reinstall exits 0" [ $? -eq 0 ]
check "reinstall removes a stale uncompressed copy" [ ! -e "$DEST/obfuscate.1" ]

# Missing source
OUT=$(SRCROOT="$WORK/empty" MAN_DEST_DIR="$DEST" "$SCRIPT_DIR/install-man-page.sh" 2>&1)
check "missing source exits non-zero" [ $? -ne 0 ]
check "missing source reports an error:" sh -c 'echo "$1" | grep -q "^error:"' _ "$OUT"

# Unwritable destination
if $IS_ROOT; then
    echo "  ⏭️  skipping unwritable-destination tests (running as root)"
else
    LOCKED="$WORK/locked-man"
    mkdir -p "$LOCKED" && chmod 555 "$LOCKED"
    OUT=$(SRCROOT="$SRCROOT" MAN_DEST_DIR="$LOCKED" "$SCRIPT_DIR/install-man-page.sh" 2>&1)
    check "unwritable destination exits 0" [ $? -eq 0 ]
    check "unwritable destination reports a warning:" sh -c 'echo "$1" | grep -q "^warning:"' _ "$OUT"
    check "unwritable destination installs nothing" [ -z "$(ls "$LOCKED")" ]
fi

echo "install-binary.sh"

# A tiny unsigned binary stands in for the real one. Like Xcode's product at
# the time the Run Script phase runs, it has no code signature.
PRODUCTS="$WORK/products"
mkdir -p "$PRODUCTS"
if ! printf 'int main(void) { return 0; }\n' |
    cc -x c - -o "$PRODUCTS/obfuscate" -Wl,-no_adhoc_codesign 2>/dev/null; then
    echo "  ❌ couldn't compile the test binary (is the Xcode toolchain installed?)"
    exit 1
fi

# Normal install
BIN="$WORK/bin"
OUT=$(BUILT_PRODUCTS_DIR="$PRODUCTS" BIN_DEST_DIR="$BIN" "$SCRIPT_DIR/install-binary.sh" 2>&1)
check "exits 0 on a normal install" [ $? -eq 0 ]
check "installs the binary" [ -f "$BIN/obfuscate" ]
check "installed binary is executable" [ -x "$BIN/obfuscate" ]
check "installed binary has a valid signature" codesign --verify "$BIN/obfuscate"
check "installed binary runs" "$BIN/obfuscate"
check "built product is left unmodified" sh -c '! codesign --verify "$1" 2>/dev/null' _ "$PRODUCTS/obfuscate"
check "leaves no temporary files" [ "$(ls "$BIN")" = "obfuscate" ]

# Reinstall over an existing binary
BUILT_PRODUCTS_DIR="$PRODUCTS" BIN_DEST_DIR="$BIN" "$SCRIPT_DIR/install-binary.sh" > /dev/null 2>&1
check "reinstall exits 0" [ $? -eq 0 ]

# Xcode always exports INSTALL_DIR (as /tmp/<project>.dst/...); it must be ignored
BIN2="$WORK/bin2"
INSTALL_DIR="$WORK/xcode-install-dir" BUILT_PRODUCTS_DIR="$PRODUCTS" BIN_DEST_DIR="$BIN2" \
    "$SCRIPT_DIR/install-binary.sh" > /dev/null 2>&1
check "ignores Xcode's INSTALL_DIR: installs to BIN_DEST_DIR" [ -f "$BIN2/obfuscate" ]
check "ignores Xcode's INSTALL_DIR: nothing written there" [ ! -e "$WORK/xcode-install-dir" ]

# BUILT_PRODUCTS_DIR not set
OUT=$(env -u BUILT_PRODUCTS_DIR BIN_DEST_DIR="$BIN" "$SCRIPT_DIR/install-binary.sh" 2>&1)
check "unset BUILT_PRODUCTS_DIR exits non-zero" [ $? -ne 0 ]
check "unset BUILT_PRODUCTS_DIR reports an error:" sh -c 'echo "$1" | grep -q "^error:"' _ "$OUT"

# Missing binary
OUT=$(BUILT_PRODUCTS_DIR="$WORK/empty" BIN_DEST_DIR="$BIN" "$SCRIPT_DIR/install-binary.sh" 2>&1)
check "missing binary exits non-zero" [ $? -ne 0 ]
check "missing binary reports an error:" sh -c 'echo "$1" | grep -q "^error:"' _ "$OUT"

# Unwritable destination
if $IS_ROOT; then
    echo "  ⏭️  skipping unwritable-destination tests (running as root)"
else
    LOCKED="$WORK/locked-bin"
    mkdir -p "$LOCKED" && chmod 555 "$LOCKED"
    OUT=$(BUILT_PRODUCTS_DIR="$PRODUCTS" BIN_DEST_DIR="$LOCKED" "$SCRIPT_DIR/install-binary.sh" 2>&1)
    check "unwritable destination exits 0" [ $? -eq 0 ]
    check "unwritable destination reports a warning:" sh -c 'echo "$1" | grep -q "^warning:"' _ "$OUT"
    check "unwritable destination installs nothing" [ -z "$(ls "$LOCKED")" ]
fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
