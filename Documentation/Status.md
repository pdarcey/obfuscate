# Status

*Last updated: 25 September 2026*

## Summary

**Version 1.0.0.** The tool is feature-complete for 1.0: plain and named (`--key`) secrets, `--check`, `-f`, and `--version`. It builds in Swift 6 mode for macOS 26 with zero warnings and zero SwiftLint findings. Current work is project housekeeping and unit tests (#411).

## Health

| Area | State |
|---|---|
| Build | ✅ Swift 6, macOS 26, no warnings |
| SwiftLint | ✅ 0 findings (tool). The generated file passes the default rules. |
| End-to-end tests | ✅ `Scripts/test-obfuscate.sh`: 145 passing |
| Install-script tests | ✅ `Scripts/test-install-scripts.sh`: 33 passing |
| Unit tests | ✅ `ObfuscateKit`: 39 Swift Testing tests in 8 suites (`swift test`; not runnable from Xcode, see CLAUDE.md) |
| All suites | ✅ `Scripts/test-all.sh` |
| Dependencies | swift-argument-parser 1.8.2 (upgraded from 1.6.2 when ObfuscateKit was added) |
| Docs | ✅ Readme (example checked by tests), man page 1.0.0, MIT LICENSE |

## Completed on 25 September 2026

- **#413:** build no longer fails installing the man page; the installed binary is signed (it was killed with exit 137)
- **#412** (urgent): generated file no longer contains plaintext secrets; `--key name=secret`
- **#410, #415:** stdout carries only the generated Swift; `-f` writes only to the file; correct exit codes; `--check` reports names only
- **#407:** no `try!`; `ObfuscateError` (all four `LocalizedError` properties); throwing `Secrets` accessors; template moved to `GeneratedSource`
- **#416, #417:** generated file is warning-free in Swift 6 and passes SwiftLint (`alice`/`bob`, wrapped lines)
- **#409:** Swift 6 language mode, macOS 26 deployment target; Debug installs noted in the build log
- **#418:** `--version` (1.0.0) and an overview in `-h`
- **#406, #408, #420:** Readme and man page rewritten; MIT licence; reserved `ObfuscateError` name fixed

## Open

- **#411:** standard project files ✅, Documentation ✅, unit tests ✅, SwiftLint build phase ⏳
- **#419:** unknown option on its own reports the wrong error
- **#414:** read secrets from stdin
