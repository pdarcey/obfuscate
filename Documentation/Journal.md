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

Around the kitchen sits the **delivery van**: two shell scripts in `Scripts/` that Xcode runs on every build to install the tool and its man page into `/usr/local`.

## 3. The Codebase Map

```
obfuscate/                The tool itself
  obfuscate.swift         The command: options, validation, generate(), check, crypto
  NamedSecret.swift       --key parsing and the reserved-names list
  GeneratedSource.swift   The template for Secrets.swift
  ObfuscateError.swift    What goes wrong, why, and what to do about it
  StandardError.swift     print(…, to: &standardError)
  UInt8+HexLiteral.swift  0x0F formatting, without String(format:)
  obfuscate.1             The man page
Scripts/                  install-binary.sh, install-man-page.sh, and their tests;
                          test-obfuscate.sh, the end-to-end suite
Documentation/            You are here
```

Lost? Start at `generate()` in `obfuscate.swift`, which reads top to bottom like the recipe it is.

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

### "Aha!" moments

- **Test the test.** For every bug fix, the new tests were run against the *previous* build first. If a test passes on the buggy code, it isn't testing anything.
- **Mask the randomness.** The output is random every run, so comparing it seemed impossible, until we replaced every `0xNN` with a placeholder. Suddenly a pure refactor could be proven byte-identical, and the Readme's example could be checked on every test run.
- **ArgumentParser only prints `errorDescription`.** We found this by reading its source, not by guessing. `LocalizedError` has four properties (`errorDescription`, `failureReason`, `recoverySuggestion`, `helpAnchor`), so we print the rest ourselves.

## 6. Engineer's Wisdom

- **A tool's output is its API.** stdout, stderr and exit codes are a contract. Pipes and scripts depend on them just as much as code depends on a function signature.
- **Never echo a secret, even in an error.** The text before `=` in `--key abc/def==` might be *part of the secret*, so errors refer to "`--key #1`" instead.
- **Fail loudly, but let the caller decide.** `try!` crashes; a throwing accessor lets the app log the error and carry on without the feature. Choose the latter for anything shipped inside someone else's app.
- **Generated code is a guest in someone else's house.** It must compile without warnings in *their* strictest settings, and pass *their* linter. We test exactly that.
- **Make illegal states unrepresentable, then test the edges anyway.** Validation plus 145 end-to-end tests beats hoping.

## 7. If I Were Starting Over...

- **Put the logic in a library from day one.** A command-line target can't be imported by unit tests, so real unit tests need the core in a package. We're doing that now (`ObfuscateKit`), but it's easier at the start.
- **Write the "never leak a secret" test first.** It's the tool's reason for existing, so it should have been the first test, not a bug fix.
- **Read secrets from stdin.** Arguments end up in shell history. It's on the list (#414).
- **Keep install out of Debug builds, or at least say so.** We chose to keep it, with a note in the build log, because trying a change straight after ⌘B is genuinely handy.
