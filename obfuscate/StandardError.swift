//
/*
 Project: obfuscate
 File: StandardError

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import Foundation

/// A text output stream that writes to standard error.
///
/// Standard output is reserved for the generated Swift, so it can be piped or redirected
/// (`obfuscate KEY > Secrets.swift`). Everything else, such as status messages, errors and
/// `--check` results, goes here instead:
///
/// ```swift
/// var standardError = StandardError()
/// print("Saved to Secrets.swift", to: &standardError)
/// ```
struct StandardError: TextOutputStream {
    /// Writes `string` to standard error, unbuffered.
    mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
