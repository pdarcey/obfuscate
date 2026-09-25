# Obfuscate

## Overview

`obfuscate` is a macOS command-line tool that generates `Secrets.swift`: a `Secrets` enum with one throwing property per secret (typically an API key). Each secret is encrypted with ChaCha20-Poly1305 (CryptoKit) using its own random key, so the generated file can be committed without any secret appearing in plain text. It's obfuscation, not real security: the key is in the same file.

Current version: **1.0.0** (`Obfuscate.version` in `obfuscate/obfuscate.swift`).

## Tech Stack

- Language: Swift 6 language mode (complete strict concurrency), built with Xcode 27
- Platform: macOS 26 or later
- Frameworks: CryptoKit, Foundation, [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.8.2 (pinned in `Package.resolved`, which is deliberately tracked)
- Database: none
- Issue tracking: Clarity (project "obfuscate")

## Commands

- **Build:** Product ▸ Build (⌘B) in Xcode, or via the Xcode MCP `BuildProject`. Every build installs `obfuscate` to `/usr/local/bin` and the man page to `/usr/local/share/man/man1` (Debug builds add a note to the build log).
- **Release build:** `xcodebuild -scheme obfuscate -configuration Release build`
- **All tests:** `Scripts/test-all.sh` (unit, end-to-end and install-script suites, with a one-line summary each; run before every commit)
- **Unit tests:** `cd ObfuscateKit && swift test` (Swift Testing)
- **End-to-end tests:** `Scripts/test-obfuscate.sh` (tests the `obfuscate` on the `PATH`, or `OBFUSCATE=/path/to/obfuscate`)
- **Build-script tests:** `Scripts/test-install-scripts.sh` (the install and SwiftLint scripts; uses temporary folders only)
- **Lint:** runs in every Xcode build (`Scripts/swiftlint.sh`, a Run Script phase): findings show as build warnings, and error-level findings fail the build. From the terminal: `Scripts/swiftlint.sh` or `swiftlint`. Must report 0 findings before committing.

## Architecture

```
obfuscate/                    The command-line tool (synchronised Xcode group); only the command-line parts
  obfuscate.swift             @main ParsableCommand: options, validation, generate(), --check output
  StandardError.swift         TextOutputStream for stderr
  obfuscate.1                 The man page (installed by the build)
ObfuscateKit/                 Local Swift package with the core logic, linked to the obfuscate target
  Sources/ObfuscateKit/
    NamedSecret.swift         Parses and validates --key name=secret; generated names (apiKey1, …); reserved names
    SecretList.swift          Builds the full, validated list of secrets (order, duplicates, none)
    InputError.swift          LocalizedError for bad input (the tool turns it into a usage error, exit 64)
    SecretCipher.swift        ChaCha20-Poly1305 encrypt/decrypt with a new random key per secret
    EncryptedSecret.swift     The sealed box (alice) and key (bob)
    RoundTripResult.swift     One --check result, with a report that never includes the secret
    GeneratedSource.swift     The template for the generated Secrets.swift
    ObfuscateError.swift      LocalizedError for encryption/decryption failures
    UInt8+HexLiteral.swift    0x0F-style byte literals
  Tests/ObfuscateKitTests/    Swift Testing unit tests
Scripts/                      Build-phase scripts and the shell test suites
Documentation/                This file, Journal, Plan, Status
```

Flow: `run()` → `generate()` → `allSecrets()` (`SecretList.make`) → `SecretCipher.encrypt` each → `GeneratedSource.property` / `.file` → optional `verifyRoundTrip` (`RoundTripResult` per secret, for `--check`) → write to `-f` file or stdout.

Put new logic in `ObfuscateKit` (with unit tests); keep the tool to argument parsing and I/O. `ObfuscateKit` must not depend on ArgumentParser.

## Environment Variables

None required by the tool. The scripts read (all optional, with defaults):

- `OBFUSCATE`: the binary for `test-obfuscate.sh`
- `BIN_DEST_DIR`, `MAN_DEST_DIR`: install destinations for the install scripts
- Xcode-supplied: `SRCROOT`, `PRODUCT_NAME`, `BUILT_PRODUCTS_DIR`, `CONFIGURATION`, `EXPANDED_CODE_SIGN_IDENTITY`

## Conventions

- **Never hand-edit `project.pbxproj`.** Use the Xcode MCP (`XcodeWrite` to add files, `UpdateTargetBuildSetting`), or give Paul step-by-step Xcode instructions (e.g. for Run Script phases).
- **Never output a secret.** Not in the generated file (not even a comment), not in error messages (identify a bad `--key` by position, e.g. `--key #2`), not in `--check` output (names only).
- **stdout carries only the generated Swift.** Everything else goes to stderr via `StandardError`. With `-f`, nothing goes to stdout.
- **Exit codes:** 0 success; 1 failed check/write/encryption (`ExitCode.failure`); 64 usage errors (ArgumentParser's `ValidationError`).
- **The generated file must stay clean in apps:** compile with `-swift-version 6 -warnings-as-errors`, pass SwiftLint's default rules, lines ≤ 120 characters, exactly one trailing newline. The tests enforce this.
- **Keep the Readme example in sync:** `test-obfuscate.sh` runs the command after `<!-- sample-command -->` and compares its output with the block between the `sample-output` markers (bytes masked). If you change the generated format, regenerate that block.
- **Reserved `--key` names** (`NamedSecret.reservedNames`) must include every member of the generated `Secrets` enum. Add to it whenever the template gains a member (a unit test fails if you forget).
- Every new behaviour gets tests: unit tests in `ObfuscateKit` for logic, and the shell suites for the tool's output, exit codes and files.
- Australian English in comments and docs; DocC comments on all types and functions; one type per file.

## Gotchas

- **`INSTALL_DIR` is an Xcode build setting** (`/tmp/<project>.dst/usr/local/bin`). The install script uses `BIN_DEST_DIR` instead. Don't rename it.
- **Run Script phases run before Xcode's CodeSign step**, so `install-binary.sh` signs the installed copy itself. An unsigned binary is killed on launch with exit 137.
- **ArgumentParser only prints `errorDescription`** for a thrown `LocalizedError`, so `run()` catches `ObfuscateError` and prints the full message itself.
- **ArgumentParser runs `validate()` before reporting unknown options**, so `obfuscate -v` alone says "Provide at least one secret" (#419).
- **SourceKit shows "No such module 'ArgumentParser'"** and cross-file "Cannot find type" errors when indexing files on their own. The real Xcode build is authoritative.
- **Don't run an edit and a build in the same parallel batch.** The build may not include the edit.
- **Xcode can't run ObfuscateKit's unit tests from this project.** A local package added as a dependency doesn't expose its test target: it can't be added to the `obfuscate` scheme or a test plan, and the auto-generated `ObfuscateKit` scheme runs 0 tests. Use `swift test` or `Scripts/test-all.sh`. (Opening `ObfuscateKit/Package.swift` on its own does give ⌘U.)
- **Adding or changing packages in Xcode re-resolves dependencies.** Check `Package.resolved` in the diff for unintended version changes.
