# Plan

Issues are tracked in Clarity (project "obfuscate"). This is the order of work; Clarity has the details.

Before starting: build in Xcode (it installs the tool), then run `Scripts/test-all.sh`. All three suites should pass.

## Next

### 1. #419: unknown option on its own reports the wrong error

`obfuscate -v` (or `obfuscate --bogus`) with no secrets says "Provide at least one secret" rather than "Unknown option '-v'", because ArgumentParser runs `validate()` before it reports unknown options. It still exits 64, so this is only about the message.

Suggested approach:
- Keep the per-`--key` checks in `validate()`, but move the "no secrets at all" check (`InputError.noSecrets`) to `run()`/`generate()`, so ArgumentParser's unknown-option error wins.
- Unit test in `ObfuscateKit` if any logic moves there; end-to-end tests in `test-obfuscate.sh` for `obfuscate -v` and `obfuscate --bogus` ("Unknown option", exit 64, no secret echoed), and for no arguments at all (still "Provide at least one secret").

### 2. #414: read secrets from stdin

Secrets passed as arguments end up in shell history and are briefly visible in `ps`.

To decide with Paul first:
- The interface: a `--stdin` flag, and/or reading stdin automatically when there are no arguments and stdin isn't a terminal. One secret per line?
- Naming: how `--key name=secret` works with stdin (for example, lines of `name=secret`).
- An interactive prompt with echo turned off, when stdin is a terminal.

Then: the logic in `ObfuscateKit` with unit tests, the tool's I/O, end-to-end tests (secrets never echoed), and updates to the man page, Readme and `-h`. Update the CAVEATS section, which currently only has the `HIST_IGNORE_SPACE` tip.

### 3. #421: Clarity shows v0.0.1

Set the target's `MARKETING_VERSION` to 1.0.0 (Xcode MCP `UpdateTargetBuildSetting`) so it matches `Obfuscate.version`, keep the two in sync (a test, or a note in CLAUDE.md), then `project_refresh` in Clarity. Paul also needs to update the project's help text in the Clarity app, because it still shows the old Readme.

## Ideas (not yet in Clarity)

- A Release/`make install` path, if installing Debug builds on every ⌘B becomes a nuisance.
- A Homebrew tap, if the tool is shared more widely.

## Done

- **1.0.0:** #406, #407, #408, #409, #410, #412, #413, #415, #416, #417, #418, #420
- **Project housekeeping:** #411 (`.gitignore`, `.swiftlint.yml`, `Documentation/`, `ObfuscateKit` with unit tests, `test-all.sh`, SwiftLint build phase)

See `Status.md` for details.
