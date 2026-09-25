//
/*
 Project: obfuscate
 File: ObfuscateError

 Created by Paul Darcey on 25/9/2026

 © 2026 Xerodonia Pty Ltd. All rights reserved

 ---------------------------------------------------- */

import Foundation

/// Errors thrown while encrypting or decrypting secrets.
///
/// None of these should ever happen: they mean CryptoKit itself has failed. They exist so a failure
/// is reported clearly and the tool exits with an error, rather than crashing on a `try!`.
///
/// - Important: No case carries the secret itself, so none of the messages can reveal it.
enum ObfuscateError: Error, LocalizedError {
    /// CryptoKit couldn't encrypt a secret.
    case encryptionFailed(underlying: any Error)

    /// CryptoKit couldn't decrypt a secret.
    case decryptionFailed(underlying: any Error)

    /// A secret decrypted successfully, but the result isn't valid UTF-8 text.
    case invalidUTF8

    /// What went wrong.
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            "Couldn't encrypt a secret."
        case .decryptionFailed:
            "Couldn't decrypt a secret."
        case .invalidUTF8:
            "A decrypted secret isn't valid UTF-8 text."
        }
    }

    /// Why it went wrong.
    var failureReason: String? {
        switch self {
        case .encryptionFailed(let underlying), .decryptionFailed(let underlying):
            "CryptoKit reported: \(underlying.localizedDescription)"
        case .invalidUTF8:
            "The decrypted bytes don't form a valid UTF-8 string."
        }
    }

    /// What the user can do about it.
    var recoverySuggestion: String? {
        "This should never happen. Please report it, with the command you ran (but not your secrets)."
    }

    /// There's no Help Book for a command-line tool, so there's nothing to link to.
    var helpAnchor: String? {
        nil
    }

    /// The description, reason and suggestion together, one per line, for printing to stderr.
    ///
    /// ArgumentParser only prints ``errorDescription`` for a thrown error, so the tool uses this
    /// to show the user all three.
    var fullMessage: String {
        [errorDescription, failureReason, recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
