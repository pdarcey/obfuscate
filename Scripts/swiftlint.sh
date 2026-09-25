#!/bin/sh
#
# swiftlint.sh
#
# Lints the project with SwiftLint, using .swiftlint.yml in the project root.
#
# Runs from an Xcode "Run Script" build phase, where findings appear as build
# warnings and errors, or directly from the terminal:
#
#     Scripts/swiftlint.sh
#
# Environment (all optional; Xcode supplies SRCROOT):
#   SRCROOT    Project root. Defaults to the parent of this script's folder.
#   SWIFTLINT  The swiftlint binary. Defaults to swiftlint on the PATH (including
#              Homebrew's folders, which Xcode's build environment leaves out).
#
# Exit status:
#   0  No error-level findings (warnings are allowed), or SwiftLint isn't
#      installed (reported as a warning, so the build still works).
#   2  SwiftLint found error-level violations, which fail the build.
#
# © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRCROOT=${SRCROOT:-$(dirname "$SCRIPT_DIR")}

# Xcode's build environment has a minimal PATH, so add Homebrew's usual locations.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
SWIFTLINT=${SWIFTLINT:-$(command -v swiftlint || true)}

if [ -z "$SWIFTLINT" ] || [ ! -x "$SWIFTLINT" ]; then
    echo "warning: SwiftLint isn't installed, so the code wasn't linted. Install it with: brew install swiftlint" >&2
    exit 0
fi

cd "$SRCROOT" || exit 1
# The default "xcode" reporter prints findings in the form Xcode shows as issues.
exec "$SWIFTLINT" lint --quiet
