#!/bin/sh
#
# install-binary.sh
#
# Copies the built command-line tool into a bin directory on the PATH.
#
# Runs from an Xcode "Run Script" build phase, or directly from the terminal:
#
#     BUILT_PRODUCTS_DIR=/path/to/Build/Products/Debug Scripts/install-binary.sh
#
# Environment (Xcode supplies BUILT_PRODUCTS_DIR and PRODUCT_NAME):
#   BUILT_PRODUCTS_DIR  Folder containing the built binary. Required.
#   PRODUCT_NAME        Tool name. Defaults to "obfuscate".
#   BIN_DEST_DIR        Destination. Defaults to /usr/local/bin.
#   EXPANDED_CODE_SIGN_IDENTITY
#                       Identity used to sign the installed copy. Defaults to
#                       "-" (ad-hoc).
#   CONFIGURATION       Build configuration (Debug, Release, ...). When it's
#                       Debug, a note in the build log says so, because the
#                       installed tool is then an unoptimised Debug build.
#
# Xcode runs Run Script phases before its own CodeSign step, so the binary this
# script sees is unsigned. macOS kills unsigned binaries on Apple silicon, so
# the installed copy is signed here.
#
# Note: don't rename BIN_DEST_DIR to INSTALL_DIR. Xcode already defines
# INSTALL_DIR (as /tmp/<project>.dst/usr/local/bin) for every build.
#
# Exit status:
#   0  Installed, or skipped with a warning because the destination isn't
#      writable.
#   1  BUILT_PRODUCTS_DIR isn't set, the built binary is missing, or signing
#      the installed copy failed.
#
# © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

set -eu

PRODUCT_NAME=${PRODUCT_NAME:-obfuscate}
BIN_DEST_DIR=${BIN_DEST_DIR:-/usr/local/bin}
SIGN_IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:--}

if [ -z "${BUILT_PRODUCTS_DIR:-}" ]; then
    echo "error: BUILT_PRODUCTS_DIR isn't set. Set it to the folder containing the built $PRODUCT_NAME binary." >&2
    exit 1
fi

SOURCE="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME"
DEST="$BIN_DEST_DIR/$PRODUCT_NAME"

if [ ! -f "$SOURCE" ]; then
    echo "error: Built binary not found at $SOURCE" >&2
    exit 1
fi

if ! mkdir -p "$BIN_DEST_DIR" 2>/dev/null || [ ! -w "$BIN_DEST_DIR" ]; then
    echo "warning: Can't write to $BIN_DEST_DIR, so $PRODUCT_NAME wasn't installed." \
        "To fix, run: sudo chown \$(id -un) $BIN_DEST_DIR" >&2
    exit 0
fi

# Copy to a temporary file, then move it into place. Replacing the file (rather
# than overwriting it in place) avoids macOS killing the new binary because of
# a stale code-signature cache for the old one.
TMP="$DEST.tmp.$$"
trap 'rm -f "$TMP"' EXIT
cp -f "$SOURCE" "$TMP"
chmod 755 "$TMP"
if ! codesign --force --sign "$SIGN_IDENTITY" "$TMP"; then
    echo "error: Couldn't sign the installed copy of $PRODUCT_NAME with identity '$SIGN_IDENTITY'." >&2
    exit 1
fi
mv -f "$TMP" "$DEST"

echo "✅ Installed $PRODUCT_NAME to $BIN_DEST_DIR"

# Every build installs, including Debug builds, so make it obvious which one is installed.
if [ "${CONFIGURATION:-}" = "Debug" ]; then
    echo "note: Installed a Debug build of $PRODUCT_NAME. Build Release for an optimised binary."
fi
