//
/*
 Project: obfuscate
 File: NamedSecret

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import ArgumentParser

/// A secret to obfuscate, paired with the name of the generated `Secrets` property that returns it.
///
/// Names come from one of two places:
/// - `--key name=secret` on the command line, parsed with ``init(parsing:position:)``
/// - a plain positional secret, which gets a generated name (`apiKey1`, `apiKey2`, …) from ``init(value:number:)``
///
/// - Important: ``value`` is the plaintext secret. It must never be written to the generated file,
///   and never included in an error message.
struct NamedSecret: Equatable {
    /// Names that can't be used for a generated property: Swift keywords, plus the members
    /// the generated `Secrets` enum already has.
    static let reservedNames: Set<String> = [
        // Existing members of the generated `Secrets` enum
        "decrypt", "ObfuscateError",
        // Swift keywords that would stop the generated file compiling
        "_", "Any", "Self", "Type", "as", "associatedtype", "await", "break", "case", "catch", "class",
        "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough",
        "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal",
        "is", "let", "nil", "open", "operator", "precedencegroup", "private", "protocol", "public",
        "repeat", "rethrows", "return", "self", "static", "struct", "subscript", "super", "switch",
        "throw", "throws", "true", "try", "typealias", "var", "where", "while"
    ]

    /// The name of the generated `Secrets` property.
    let name: String

    /// The plaintext secret. Never written to the generated file.
    let value: String

    /// `true` when ``name`` was generated (`apiKey1`, …) rather than chosen by the user.
    let hasGeneratedName: Bool

    /// Creates a secret with a generated name, for a secret passed as a plain argument.
    /// - Parameters:
    ///   - value: The plaintext secret.
    ///   - number: The secret's 1-based position among the unnamed secrets, giving `apiKey<number>`.
    init(value: String, number: Int) {
        self.name = "apiKey\(number)"
        self.value = value
        self.hasGeneratedName = true
    }

    /// Parses a `--key` argument of the form `name=secret`.
    ///
    /// The name is everything before the **first** `=`, so the secret itself may contain `=`
    /// (for example, base64 padding).
    ///
    /// Error messages identify the argument by its position rather than echoing it, because the
    /// text before `=` may actually be part of a secret (e.g. `--key abc/def==` with no name).
    ///
    /// - Parameters:
    ///   - argument: The raw `--key` value.
    ///   - position: The 1-based position of this `--key` on the command line, used in error messages.
    /// - Throws: `ValidationError` if there's no `=`, the name isn't a valid Swift identifier,
    ///   the name is reserved, or the secret is empty.
    init(parsing argument: String, position: Int) throws {
        guard let separator = argument.firstIndex(of: "=") else {
            throw ValidationError("--key #\(position) must be in the form name=secret, but it has no '='.")
        }

        let name = String(argument[..<separator])
        let value = String(argument[argument.index(after: separator)...])

        guard Self.isValidIdentifier(name) else {
            throw ValidationError(
                "--key #\(position): the name before '=' must start with a letter or underscore, "
                + "and contain only letters, digits and underscores."
            )
        }
        guard !Self.reservedNames.contains(name) else {
            throw ValidationError(
                "--key #\(position): '\(name)' is reserved in Swift or in Secrets. Choose another name."
            )
        }
        guard !value.isEmpty else {
            // Don't echo `name`: `--key QWxh=` may be an unnamed base64 secret, not a name.
            throw ValidationError("--key #\(position): the secret after '=' is empty.")
        }

        self.name = name
        self.value = value
        self.hasGeneratedName = false
    }

    /// Whether `name` is a plain ASCII Swift identifier: a letter or underscore, followed by
    /// letters, digits or underscores.
    static func isValidIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
