# Plan

Issues are tracked in Clarity (project "obfuscate"). This is the order of work; Clarity has the details.

## In progress

### #411: Standard project files and unit tests

1. ✅ `.gitignore`, `.swiftlint.yml`, `.claude/` folders
2. ✅ `Documentation/` (CLAUDE.md, Journal, Plan, Status) and a root `CLAUDE.md` that imports `Documentation/CLAUDE.md`
3. ✅ Unit tests (Swift Testing), via a local Swift package:
   - Move the core logic into `ObfuscateKit/`: `NamedSecret`, `GeneratedSource`, `ObfuscateError`, `UInt8.hexLiteral`, and a new `SecretCipher` (encrypt/decrypt)
   - Make `verifyRoundTrip` return results, so the failed-check path can be unit tested (the gap left by #410)
   - Paul adds the local package to the Xcode project (File ▸ Add Package Dependencies ▸ Add Local…)
   - Tests run with `swift test` and in Xcode
4. ⏳ SwiftLint build phase: `Scripts/swiftlint.sh`, called from a Run Script phase that Paul adds in Xcode

## Next

- **#419:** `obfuscate -v` (an unknown option on its own) says "Provide at least one secret" instead of "Unknown option". Move the "at least one secret" check out of `validate()`.
- **#414:** read secrets from stdin (`--stdin`, or a prompt with echo off), so they stay out of shell history and `ps`.

## Done (1.0.0)

#406, #407, #408, #409, #410, #412, #413, #415, #416, #417, #418, #420. See `Status.md`.
