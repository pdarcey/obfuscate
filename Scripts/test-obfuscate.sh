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
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT

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

# check_decodes <file> <property> <expected> [<property> <expected> ...]
# Compiles <file> with a tiny program that prints each property, and checks
# each one decodes to its expected secret.
check_decodes() {
    local file=$1
    shift
    local properties=() expected=()
    while [ $# -gt 0 ]; do
        properties+=("$1")
        expected+=("$2")
        shift 2
    done

    for property in "${properties[@]}"; do
        echo "print(try Secrets.$property)"
    done > main.swift

    if ! swiftc -o decode "$file" main.swift > compile.log 2>&1; then
        fail "$file compiles"
        sed 's/^/      /' compile.log
        return
    fi
    pass "$file compiles"

    local i=0 decoded
    while IFS= read -r decoded; do
        check "${properties[$i]} decodes to the original secret" [ "$decoded" = "${expected[$i]}" ]
        i=$((i + 1))
    done < <(./decode)
    check "decodes every secret in $file" [ "$i" -eq "${#properties[@]}" ]
}

echo "Generated file must compile and decode"

ARGS=()
for i in "${!SECRETS[@]}"; do
    ARGS+=("apiKey$((i + 1))" "${SECRETS[$i]}")
done
check_decodes Secrets.swift "${ARGS[@]}"

echo "Named secrets (--key name=secret)"

NAMED_1="sk-live-named-openai-9d8c7b"
NAMED_2="pk=with=equals=signs=="
PLAIN="plain-unnamed-secret-5e4f"
STDOUT=$("$OBFUSCATE" -f Named --key "openAI=$NAMED_1" -k "stripe_2=$NAMED_2" -- "$PLAIN" 2>&1)
check "exits 0" [ $? -eq 0 ]
check "names a property openAI" grep -q 'static var openAI: String' Named.swift
check "names a property stripe_2" grep -q 'static var stripe_2: String' Named.swift
check "names the plain secret apiKey1" grep -q 'static var apiKey1: String' Named.swift
check "named properties don't ask to be renamed" [ "$(grep -c 'Rename `' Named.swift)" -eq 1 ]
for secret in "$NAMED_1" "$NAMED_2" "$PLAIN"; do
    check "file doesn't contain: $secret" sh -c '! grep -qF -- "$1" Named.swift' _ "$secret"
    check "stdout doesn't contain: $secret" sh -c '! printf "%s" "$2" | grep -qF -- "$1"' _ "$secret" "$STDOUT"
done
check_decodes Named.swift openAI "$NAMED_1" stripe_2 "$NAMED_2" apiKey1 "$PLAIN"

echo "Invalid input is rejected, without echoing secrets"

# rejects <description> <secret that must not be echoed> <expected message> <obfuscate args...>
rejects() {
    local description=$1 secret=$2 expected=$3
    shift 3
    rm -f Rejected.swift
    local output
    output=$("$OBFUSCATE" -f Rejected "$@" 2>&1)
    check "$description: exits non-zero" [ $? -ne 0 ]
    check "$description: explains why" sh -c 'printf "%s" "$2" | grep -qF -- "$1"' _ "$expected" "$output"
    check "$description: writes no file" [ ! -e Rejected.swift ]
    check "$description: doesn't echo the secret" sh -c '! printf "%s" "$2" | grep -qF -- "$1"' _ "$secret" "$output"
}

rejects "no secrets at all" "(none)" "Provide at least one secret"
rejects "--key without '='" "sk-noequals-secret-123" "has no '='" \
    --key "sk-noequals-secret-123"
rejects "--key with an unnamed base64 secret" "abc/defSECRET" "the name before '=' must start with" \
    --key "abc/defSECRET=="
rejects "--key with an empty secret" "QWxhZGRpSECRET" "the secret after '=' is empty" \
    --key "QWxhZGRpSECRET="
rejects "--key name starting with a digit" "digit-secret-1" "the name before '=' must start with" \
    --key "1abc=digit-secret-1"
rejects "--key with a Swift keyword" "keyword-secret-1" "'class' is reserved" \
    --key "class=keyword-secret-1"
rejects "--key named after a Secrets member" "member-secret-1" "'decrypt' is reserved" \
    --key "decrypt=member-secret-1"
rejects "duplicate --key names" "dup-secret-1" "'dup' is used more than once" \
    --key "dup=dup-secret-1" --key "dup=dup-secret-2"
rejects "--key clashing with a generated name" "collide-secret-1" "'apiKey1' is used more than once" \
    --key "apiKey1=collide-secret-1" "plain-collide-2"
rejects "--key identifies which one is wrong" "second-bad-secret" "--key #2" \
    --key "good=first-good-secret" --key "second-bad-secret"

echo "Only the generated Swift goes to stdout"

SEP_NAMED="sep-named-secret-7a6b"
SEP_PLAIN="sep-plain-secret-3c2d"
"$OBFUSCATE" -c --key "sepName=$SEP_NAMED" "$SEP_PLAIN" > Redirected.swift 2> stderr.txt
check "-c with stdout redirected: exits 0" [ $? -eq 0 ]
check "stdout starts with the generated Swift" [ "$(head -1 Redirected.swift)" = "import Foundation" ]
check "stdout has no --check results" sh -c '! grep -qE "✅|❌|decodes" Redirected.swift'
check "--check reports each secret by name on stderr" \
    sh -c 'grep -q "✅ sepName decodes correctly" stderr.txt && grep -q "✅ apiKey1 decodes correctly" stderr.txt'
for secret in "$SEP_NAMED" "$SEP_PLAIN"; do
    check "redirected file doesn't contain: $secret" sh -c '! grep -qF -- "$1" Redirected.swift' _ "$secret"
    check "--check doesn't print: $secret" sh -c '! grep -qF -- "$1" stderr.txt' _ "$secret"
done
check_decodes Redirected.swift sepName "$SEP_NAMED" apiKey1 "$SEP_PLAIN"
check "every byte is a two-digit uppercase hex literal" \
    sh -c '[ -z "$(grep -oE "0x[0-9A-Fa-f]+" Redirected.swift | grep -vE "^0x[0-9A-F]{2}$")" ]'

"$OBFUSCATE" -f Saved "saved-secret-8e9f" > saved-stdout.txt 2> saved-stderr.txt
check "-f: exits 0" [ $? -eq 0 ]
check "-f: 'Saved to' goes to stderr" grep -q "^Saved to Saved.swift$" saved-stderr.txt
check "-f: 'Saved to' isn't on stdout" sh -c '! grep -q "Saved to" saved-stdout.txt'
check "-f: prints nothing to stdout" [ ! -s saved-stdout.txt ]
check "-f: file contains the generated Swift" [ "$(head -1 Saved.swift)" = "import Foundation" ]
check "-f: file doesn't contain the secret" sh -c '! grep -qF "saved-secret-8e9f" Saved.swift'
check_decodes Saved.swift apiKey1 "saved-secret-8e9f"

echo "Write failures exit non-zero"

mkdir -p locked && chmod 555 locked
"$OBFUSCATE" -f locked/Nope "unwritable-secret-4a5b" > locked-stdout.txt 2> locked-stderr.txt
check "unwritable -f path: exits non-zero" [ $? -ne 0 ]
check "unwritable -f path: reports an error: on stderr" grep -q "^error: Unable to write to locked/Nope.swift" locked-stderr.txt
check "unwritable -f path: prints nothing to stdout" [ ! -s locked-stdout.txt ]
check "unwritable -f path: doesn't echo the secret" sh -c '! grep -qF "unwritable-secret-4a5b" locked-stderr.txt'

echo "Generated file has no force-try, unused salt, or lossy decoding"

check "no try! in the generated file" sh -c '! grep -q "try!" Saved.swift'
check "no salt in the generated file" sh -c '! grep -qi "salt" Saved.swift'
check "no String(decoding: in the generated file" sh -c '! grep -q "String(decoding:" Saved.swift'
check "accessors are throwing getters" grep -q "get throws {" Saved.swift
check "generated file declares Secrets.ObfuscateError" \
    grep -q "enum ObfuscateError: Error, LocalizedError" Saved.swift
for property in errorDescription failureReason recoverySuggestion helpAnchor; do
    check "Secrets.ObfuscateError implements $property" grep -q "var $property: String?" Saved.swift
done

# catch_program <property>: a program that reads a secret and reports what was thrown.
catch_program() {
    cat <<SWIFT
do {
    _ = try Secrets.$1
    print("NO ERROR")
} catch let error as Secrets.ObfuscateError {
    print("CAUGHT")
    print(error.errorDescription ?? "nil")
    print(error.failureReason ?? "nil")
    print(error.recoverySuggestion ?? "nil")
    print(error.helpAnchor ?? "no help anchor")
} catch {
    print("OTHER ERROR")
}
SWIFT
}

echo "A corrupted secret throws Secrets.ObfuscateError.decryptionFailed"

# Flip the lowest bit of the first byte of apiKey1's encrypted content.
python3 - Saved.swift Corrupted.swift <<'PY'
import re, sys
source = open(sys.argv[1]).read()
match = re.search(r"let a: \[UInt8\] = \[\s*0x([0-9A-F]{2})", source)
flipped = "0x%02X" % (int(match.group(1), 16) ^ 0x01)
open(sys.argv[2], "w").write(source[:match.start(1) - 2] + flipped + source[match.end(1):])
PY
catch_program apiKey1 > main.swift
if swiftc -o corrupted Corrupted.swift main.swift > compile.log 2>&1; then
    OUTPUT=$(./corrupted 2>&1)
    check "corrupted secret: doesn't crash" [ $? -eq 0 ]
    check "corrupted secret: throws Secrets.ObfuscateError" [ "$(echo "$OUTPUT" | head -1)" = "CAUGHT" ]
    check "corrupted secret: errorDescription" sh -c 'echo "$1" | grep -qx "Couldn.t decrypt a secret."' _ "$OUTPUT"
    check "corrupted secret: failureReason" sh -c 'echo "$1" | grep -q "^CryptoKit reported: "' _ "$OUTPUT"
    check "corrupted secret: recoverySuggestion" sh -c 'echo "$1" | grep -q "Regenerate it with the obfuscate tool"' _ "$OUTPUT"
    check "corrupted secret: no helpAnchor" sh -c 'echo "$1" | grep -qx "no help anchor"' _ "$OUTPUT"
else
    fail "Corrupted.swift compiles"
    sed 's/^/      /' compile.log
fi

echo "A secret that isn't UTF-8 throws Secrets.ObfuscateError.invalidUTF8"

# Properly encrypt bytes that aren't valid UTF-8, then splice them into a generated file.
cat > seal.swift <<'SWIFT'
import CryptoKit
import Foundation
let key = SymmetricKey(size: .bits256)
let sealed = try ChaChaPoly.seal(Data([0xFF, 0xFE, 0xFD]), using: key).combined
func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { "0x" + String($0, radix: 16, uppercase: true).leftPadded }.joined(separator: ", ")
}
extension String { var leftPadded: String { count == 1 ? "0" + self : self } }
print(hex(sealed))
print(key.withUnsafeBytes { hex($0) })
SWIFT
if swiftc -o seal seal.swift > compile.log 2>&1 && ./seal > sealed.txt; then
    python3 - Saved.swift NotUTF8.swift sealed.txt <<'PY'
import re, sys
source = open(sys.argv[1]).read()
content, key = open(sys.argv[3]).read().splitlines()
source = re.sub(r"(let a: \[UInt8\] = \[\s*)[^\]]*?(\s*\])", lambda m: m.group(1) + content + m.group(2), source, count=1)
source = re.sub(r"(let b: \[UInt8\] = \[\s*)[^\]]*?(\s*\])", lambda m: m.group(1) + key + m.group(2), source, count=1)
open(sys.argv[2], "w").write(source)
PY
    catch_program apiKey1 > main.swift
    if swiftc -o notutf8 NotUTF8.swift main.swift > compile.log 2>&1; then
        OUTPUT=$(./notutf8 2>&1)
        check "non-UTF-8 secret: throws Secrets.ObfuscateError" [ "$(echo "$OUTPUT" | head -1)" = "CAUGHT" ]
        check "non-UTF-8 secret: errorDescription" \
            sh -c 'echo "$1" | grep -qx "A decrypted secret isn.t valid UTF-8 text."' _ "$OUTPUT"
        check "non-UTF-8 secret: failureReason" \
            sh -c 'echo "$1" | grep -qx "The decrypted bytes don.t form a valid UTF-8 string."' _ "$OUTPUT"
    else
        fail "NotUTF8.swift compiles"
        sed 's/^/      /' compile.log
    fi
else
    fail "helper that seals non-UTF-8 bytes compiles and runs"
    sed 's/^/      /' compile.log
fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
