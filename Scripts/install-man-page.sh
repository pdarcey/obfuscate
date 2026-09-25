#!/bin/sh
#
# install-man-page.sh
#
# Installs the tool's man page, gzipped, into a man1 directory.
#
# Runs from an Xcode "Run Script" build phase, or directly from the terminal:
#
#     Scripts/install-man-page.sh
#
# Environment (all optional; Xcode supplies SRCROOT and PRODUCT_NAME):
#   SRCROOT        Project root. Defaults to the parent of this script's folder.
#   PRODUCT_NAME   Tool name. Defaults to "obfuscate".
#   MAN_DEST_DIR   Destination. Defaults to /usr/local/share/man/man1.
#
# Exit status:
#   0  Installed, or skipped with a warning because the destination isn't
#      writable (a man page problem should never block a build).
#   1  The man page source is missing.
#
# © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRCROOT=${SRCROOT:-$(dirname "$SCRIPT_DIR")}
PRODUCT_NAME=${PRODUCT_NAME:-obfuscate}
MAN_DEST_DIR=${MAN_DEST_DIR:-/usr/local/share/man/man1}

SOURCE="$SRCROOT/$PRODUCT_NAME/$PRODUCT_NAME.1"
DEST="$MAN_DEST_DIR/$PRODUCT_NAME.1.gz"

if [ ! -f "$SOURCE" ]; then
    echo "error: Man page not found at $SOURCE" >&2
    exit 1
fi

if ! mkdir -p "$MAN_DEST_DIR" 2>/dev/null || [ ! -w "$MAN_DEST_DIR" ]; then
    echo "warning: Can't write to $MAN_DEST_DIR, so the $PRODUCT_NAME man page wasn't installed." \
        "To fix, run: sudo chown -R \$(id -un) $(dirname "$MAN_DEST_DIR")" >&2
    exit 0
fi

# Compress to a temporary file, then move it into place, so an interrupted
# install never leaves a partial man page behind.
TMP="$DEST.tmp.$$"
trap 'rm -f "$TMP"' EXIT
gzip -9 -c "$SOURCE" > "$TMP"
mv -f "$TMP" "$DEST"

# Remove any uncompressed copy left by earlier versions of this script.
rm -f "$MAN_DEST_DIR/$PRODUCT_NAME.1"

echo "Installed $PRODUCT_NAME man page to $DEST"
