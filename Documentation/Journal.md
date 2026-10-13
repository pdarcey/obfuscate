# The Obfuscate Journal

*A living record of how this little tool grew up: the bugs, the lessons, and the occasional facepalm.*

---

## 1. The Big Picture

Imagine you're building an app that talks to OpenAI or Stripe. You need an API key in the app, but you really don't want it sitting in your Git history, where it'll live forever (and where anyone who clones the repo can read it).

`obfuscate` is the friend who says: "Give me your key, and I'll hand you back a Swift file that *contains* it, but scrambled." You drop `Secrets.swift` into your app, write `try Secrets.openAI`, and the key is unscrambled at runtime. Anyone skimming your source sees a wall of hex bytes named `alice` and `bob`, not `sk-live-…`.

Is it Fort Knox? No. It's more like putting your spare key in a lockbox rather than under the doormat. A determined burglar gets in, but the casual passer-by doesn't. The Readme says so loudly, and it's important that it does.

## 2. Architecture Deep Dive

Think of the tool as a small restaurant kitchen:

- **The waiter (`Obfuscate`, the `ParsableCommand`)** takes the order: which secrets, what to name them, whether to check the food before it goes out (`--check`), and whether it's for dine-in (stdout) or takeaway (`-f`). swift-argument-parser does the note-taking, so the waiter never mishears.
- **The maître d' at the door (`NamedSecret`)** checks everyone's name before they're seated. `--key openAI=sk-…` gets in. `--key class=…` doesn't, because `class` is a Swift keyword and would break the generated file. It politely refuses without ever reading your secret aloud: bad keys are identified as "`--key #2`", never by their contents.
- **The chef (`encrypt`)** seals each secret in its own ChaCha20-Poly1305 container, with its own random key. A new key every time means every run produces different output, which is a feature, not a bug.
- **The recipe book (`GeneratedSource`)** turns sealed secrets into Swift: the `Secrets` enum, one throwing property per secret, the nested `Secrets.ObfuscateError`, and a `decrypt` function. It's all string templates, but carefully indented ones.
- **The food taster (`verifyRoundTrip`)** tastes every dish before it leaves the kitchen when you ask for `--check`, and reports "✅ openAI decodes correctly" without ever saying what it tasted like.
- **The pass (stdout vs stderr)**: only food goes out through the pass (stdout). Chatter ("Saved to…", check results, errors) goes through the back door (stderr), so `obfuscate KEY > Secrets.swift` gives you a clean file.

The kitchen itself (the maître d', the chef, the recipe book and the food taster) lives in a separate building: the local Swift package **`ObfuscateKit`**. The waiter and the pass stay in the tool. That split exists purely so the kitchen can be inspected (unit tested) without customers in the room.

Around the kitchen sits the **delivery van**: two shell scripts in `Scripts/` that Xcode runs on every build to install the tool and its man page into `/usr/local`.

## 3. The Codebase Map

```
obfuscate/                The command-line tool: just the waiter and the pass
  obfuscate.swift         The command: options, validation, generate(), --check output
  StandardError.swift     print(…, to: &standardError)
  obfuscate.1             The man page
ObfuscateKit/             The kitchen: a local Swift package with the real logic
  Sources/ObfuscateKit/   NamedSecret, SecretList, InputError, SecretCipher, EncryptedSecret,
                          RoundTripResult, GeneratedSource, ObfuscateError, UInt8+HexLiteral
  Tests/ObfuscateKitTests/  Swift Testing unit tests
Scripts/                  install-binary.sh, install-man-page.sh, swiftlint.sh (build phases);
                          test-obfuscate.sh, test-install-scripts.sh, test-all.sh (tests)
Documentation/            You are here
```

Lost? Start at `generate()` in `obfuscate.swift`, which reads top to bottom like the recipe it is, then follow the calls into `ObfuscateKit`. To check everything still works, run `Scripts/test-all.sh`.

## 4. Tech Stack & Why

- **Swift + swift-argument-parser.** Apple's argument parser gives us `--help`, `--version`, validation and exit codes for free. Writing our own would be a fine way to spend a week and end up with something worse.
- **CryptoKit's ChaChaPoly.** It's built into the OS, fast, and *authenticated*: if a single byte of the encrypted data changes, decryption fails loudly rather than returning garbage. That matters, as you'll see below.
- **Swift 6 language mode.** Complete strict concurrency checking, for free. This tool has no shared mutable state, so switching produced zero warnings, which is the best kind of migration.
- **Shell scripts for installation and end-to-end tests.** The tool's contract is "what comes out of stdout and stderr, and the exit code". The most honest way to test that is to run the real binary, exactly as a user would.

## 5. The Journey

### The binary that died instantly (exit 137)

The build installed `obfuscate` to `/usr/local/bin`, and running it did… nothing. Exit code 137 means SIGKILL: macOS was killing it on sight. The culprit was Xcode's build order. **Run Script phases run *before* the CodeSign step**, so our install script was copying an *unsigned* binary, and Apple silicon refuses to run those. The fix: the install script signs its own copy (`codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}"`). The lesson: the build log tells you the order things happen in. Read it.

### The install that went to /tmp

After moving the install scripts into files, the build proudly announced "✅ Installed obfuscate to /tmp/obfuscate.dst/usr/local/bin". Very helpful, and completely wrong. The script let you override the destination with `INSTALL_DIR`… which **Xcode already defines** for every build. Our "optional override" was always overridden. It was renamed to `BIN_DEST_DIR`, with a comment warning future us never to rename it back.

### The secret in the comment

The most embarrassing one. Every generated property began with `// Key for sk-live-…`, followed by "**Important!** Replace the above comment". In other words, a tool whose whole job is keeping secrets out of source control was *writing the secret into the file*, and relying on you to delete it. It was fixed by never emitting the secret anywhere, and guarded by a test that greps the output for every input secret. The test was run against the old binary first, to prove it would have caught the bug (it failed 12 times, which was the point).

### The man page that knew too much

`cp: Permission denied`, followed by `gzip: can't stat`. `/usr/local/share/man` was owned by root, and the script ploughed on after the first failure. Now the scripts `set -eu`, write to a temporary file then move it into place, and turn "folder not writable" into an Xcode *warning* with the exact `chown` command to fix it. A man page should never block a build.

### When `--check` leaked what it was checking

`--check` used to print "Decoding produces: sk-live-…" to stdout. Redirect that into `Secrets.swift` and you'd get a file that didn't compile *and* contained your secrets. Now stdout is sacred (Swift only), check results go to stderr, and they only ever mention names.

### The name that broke the build

When the generated file gained a nested `enum ObfuscateError`, nobody told the reserved-names list, which still protected the long-gone `salt`. So `--key ObfuscateError=…` happily generated a file that failed with "invalid redeclaration". It was caught while writing the man page, of all things. **Documentation is a code review.**

### The tests Xcode couldn't see

Moving the logic into `ObfuscateKit` so it could be unit tested went smoothly: 39 Swift Testing tests, all green in `swift test`. Then we tried to run them with ⌘U, and they weren't there. They couldn't be added to the app's scheme, a new test plan's "+" didn't list them, and even Xcode's own auto-generated `ObfuscateKit` scheme cheerfully ran **0 tests**. It turns out a local package that's only a *dependency* of a project keeps its test target to itself. The pragmatic answer was `Scripts/test-all.sh`: one command, three suites, eleven seconds, and a one-line verdict each. The lesson: check what the IDE will actually do before promising a workflow. (We also cleaned up the two empty test plans that our attempts left behind.)

### The upgrade nobody asked for

Adding the local package made Xcode re-resolve every package, and `swift-argument-parser` quietly moved from 1.6.2 to 1.8.2 in `Package.resolved`. Nothing broke (all the suites passed), but a dependency upgrade should be a decision, not a side effect. We kept it, said so in the commit message, and added a gotcha to CLAUDE.md: after touching packages in Xcode, read the `Package.resolved` diff.

### Proving the linter speaks Xcode

A SwiftLint build phase that "runs fine" could just as easily be silently doing nothing. So we planted a file with three trailing spaces, built, and asked the Xcode MCP for the build's warnings. There it was: "Trailing Whitespace Violation" as a proper Xcode issue with file and line. Then we deleted the plant and rebuilt to confirm the warning had gone.

### "Aha!" moments

- **Test the test.** For every bug fix, the new tests were run against the *previous* build first. If a test passes on the buggy code, it isn't testing anything.
- **Mask the randomness.** The output is random every run, so comparing it seemed impossible, until we replaced every `0xNN` with a placeholder. Suddenly a pure refactor could be proven byte-identical, and the Readme's example could be checked on every test run.
- **Keep the kitchen out of the dining room.** `ObfuscateKit` doesn't know ArgumentParser exists: it throws its own `InputError`, and the tool translates it into a usage error. The library stays testable and reusable, and the messages stay identical.
- **A guard test for a whole class of bug.** Rather than testing that `ObfuscateError` is reserved, one unit test scans the generated `Secrets` enum for *every* member and checks each is a reserved `--key` name. It caught a deliberately recreated #420, and it will catch the next one too.
- **ArgumentParser only prints `errorDescription`.** We found this by reading its source, not by guessing. `LocalizedError` has four properties (`errorDescription`, `failureReason`, `recoverySuggestion`, `helpAnchor`), so we print the rest ourselves.

### A face for the tool (13 October 2026)

`obfuscate` got a logo: a grid of hex bytes with half the cells blanked out in mint green, which is the whole tool in one picture. Paul chose it from five drafts, and all six of the command-line tools got the same treatment in one sitting, each with its own colour family so they can't be mistaken for one another.

Two small things worth remembering:

- **Markdown can't size an image.** `![logo](logo.png)` would show the full 1024 pixels, so the Readme uses `<img src="logo.png" width="128">`. `test-obfuscate.sh` reads the Readme to check the sample output, so we re-ran it after the edit (145 still passing). A Readme that tests depend on is code, and gets tested like code.
- **The SVG keeps its digits as live text.** `logo.svg` draws the hex digits in Menlo. On a machine without Menlo they'd fall back to another monospaced font. The PNG is what people actually see, so we left it; converting the digits to outlines is the fix if it ever matters.

## 6. Engineer's Wisdom

- **A tool's output is its API.** stdout, stderr and exit codes are a contract. Pipes and scripts depend on them just as much as code depends on a function signature.
- **Never echo a secret, even in an error.** The text before `=` in `--key abc/def==` might be *part of the secret*, so errors refer to "`--key #1`" instead.
- **Fail loudly, but let the caller decide.** `try!` crashes; a throwing accessor lets the app log the error and carry on without the feature. Choose the latter for anything shipped inside someone else's app.
- **Generated code is a guest in someone else's house.** It must compile without warnings in *their* strictest settings, and pass *their* linter. We test exactly that.
- **Make illegal states unrepresentable, then test the edges anyway.** Validation plus 145 end-to-end tests beats hoping.

## 7. If I Were Starting Over...

- **Put the logic in a library from day one.** A command-line target can't be imported by unit tests, so real unit tests need the core in a package. We got there (`ObfuscateKit`), but it meant a move, an Xcode step, and a detour through test plans. Starting that way costs nothing.
- **Check the IDE's workflow before promising it.** We said "tests run in Xcode too", and in this setup they don't. `swift test` and `test-all.sh` are the honest answer.
- **Write the "never leak a secret" test first.** It's the tool's reason for existing, so it should have been the first test, not a bug fix.
- **Read secrets from stdin.** Arguments end up in shell history. It's on the list (#414).
- **Keep install out of Debug builds, or at least say so.** We chose to keep it, with a note in the build log, because trying a change straight after ⌘B is genuinely handy.
