//
/*
 Project: obfuscate
 File: InputError

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import Foundation

/// Problems with the secrets given on the command line.
///
/// The command-line tool reports ``errorDescription`` as a usage error (exit status 64).
///
/// - Important: No case carries a secret, and no message includes one. A bad `--key` is identified
///   by its position, because the text before `=` may itself be part of a secret (for example,
///   `--key abc/def==` passed without a name).
public enum InputError: Error, LocalizedError, Equatable {
    /// A `--key` has no `=`, so there's no name.
    case missingSeparator(position: Int)

    /// The name before `=` in a `--key` isn't a plain ASCII Swift identifier.
    case invalidName(position: Int)

    /// The name before `=` in a `--key` is a Swift keyword or an existing member of `Secrets`.
    case reservedName(position: Int, name: String)

    /// The secret after `=` in a `--key` is empty.
    case emptySecret(position: Int)

    /// No secrets were given at all.
    case noSecrets

    /// Two secrets would produce properties with the same name.
    case duplicateName(String)

    /// What's wrong with the input, as a single line.
    public var errorDescription: String? {
        switch self {
        case .missingSeparator(let position):
            "--key #\(position) must be in the form name=secret, but it has no '='."
        case .invalidName(let position):
            "--key #\(position): the name before '=' must start with a letter or underscore, "
            + "and contain only letters, digits and underscores."
        case .reservedName(let position, let name):
            "--key #\(position): '\(name)' is reserved in Swift or in Secrets. Choose another name."
        case .emptySecret(let position):
            "--key #\(position): the secret after '=' is empty."
        case .noSecrets:
            "Provide at least one secret, either as an argument or with --key name=secret."
        case .duplicateName(let name):
            "The name '\(name)' is used more than once. Each secret needs its own name."
        }
    }

    /// Not used: ``errorDescription`` already says what's wrong and how to fix it.
    public var failureReason: String? {
        nil
    }

    /// Not used: ``errorDescription`` already says what's wrong and how to fix it.
    public var recoverySuggestion: String? {
        nil
    }

    /// There's no Help Book for a command-line tool, so there's nothing to link to.
    public var helpAnchor: String? {
        nil
    }
}
