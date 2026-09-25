//
/*
 Project: obfuscate
 File: SecretList

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

/// Builds the full, validated list of secrets to obfuscate from the command-line input.
public enum SecretList {
    /// Every secret to obfuscate: the `--key` secrets first, in order, then the plain ones as
    /// `apiKey1`, `apiKey2`, …
    /// - Parameters:
    ///   - named: The raw `--key` values, each `name=secret`.
    ///   - plain: The plain secrets passed as arguments.
    /// - Returns: The secrets, in the order their properties will appear in `Secrets`.
    /// - Throws: ``InputError`` if a `--key` is malformed, there are no secrets, or two secrets
    ///   share a name (including a `--key` name that clashes with a generated `apiKey` name).
    public static func make(named: [String], plain: [String]) throws(InputError) -> [NamedSecret] {
        var all: [NamedSecret] = []
        for (offset, argument) in named.enumerated() {
            all.append(try NamedSecret(parsing: argument, position: offset + 1))
        }
        for (offset, value) in plain.enumerated() {
            all.append(NamedSecret(value: value, number: offset + 1))
        }

        guard !all.isEmpty else {
            throw .noSecrets
        }

        var seenNames: Set<String> = []
        for secret in all where !seenNames.insert(secret.name).inserted {
            throw .duplicateName(secret.name)
        }

        return all
    }
}
