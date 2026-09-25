//
/*
 Project: obfuscate
 File: main

 Created by Paul Darcey on 3/11/2025

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import ArgumentParser
import Foundation
import ObfuscateKit

/// CLI command `obfuscate`, which generates a Swift file that obfuscates secrets such as API keys.
///
/// The generated file contains a `Secrets` enum with one throwing property per secret, so an app can read a secret
/// with `try Secrets.openAI` without the secret appearing in plain text in its source code or source control.
///
/// The generated Swift is written to stdout, or to a file with `-f`. Everything else goes to stderr.
///
/// - Note: Each time the command is run, it produces different output, because every secret is encrypted with
/// a new random key.
///
/// - Note: This method of obfuscating secrets was based on a blog post at [NSHipster](https://nshipster.com/secrets/)
///
/// - Important: This is **not** high-tech encryption. It's merely obfuscation. If *anyone* wants to crack this, it's
/// trivially easy to do so. It just means they have to be motivated enough to do *some* work, rather than have the
/// keys in plain sight.
@main
struct Obfuscate: ParsableCommand {
    /// The tool's version, shown by `obfuscate --version`. Update this for each release.
    static let version = "1.0.0"

    /// The command's overview (shown at the top of `-h`) and version.
    static let configuration = CommandConfiguration(
        abstract: "Generate a Swift file that obfuscates secrets, such as API keys.",
        version: version
    )

    /// Flag to run a check that the output file will decode the input correctly
    @Flag(
        name: .shortAndLong,
        help: "Check every secret decodes correctly before writing any output. Reports pass/fail on stderr."
    )
    var check = false

    /// You can optionally write the output to a file, so you can import it into your app
    @Option(
        name: .shortAndLong,
        help: "Write the generated Swift to this file instead of stdout. [Will add .swift, if necessary]"
    )
    var fileName: String?

    /// Secrets with a chosen property name, each given as `name=secret`
    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "A secret, and the name of the Secrets property that returns it. Repeat for more secrets.",
            valueName: "name=secret"
        )
    )
    var key: [String] = []

    /// The secret you wish to obfuscate. Typically an API key
    @Argument(help: "Secret(s) to obfuscate, separated by spaces. These become Secrets.apiKey1, apiKey2, …")
    var secrets: [String] = []

    mutating func validate() throws {
        _ = try allSecrets()
    }

    /// Every secret to obfuscate: the `--key` secrets first, in order, then the plain ones as `apiKey1`, `apiKey2`, …
    /// - Throws: `ValidationError` (a usage error, exit status 64) if there are no secrets, a `--key` is malformed,
    ///   or two secrets share a name.
    func allSecrets() throws -> [NamedSecret] {
        do {
            return try SecretList.make(named: key, plain: secrets)
        } catch {
            throw ValidationError(error.errorDescription ?? "Invalid input.")
        }
    }

    mutating func run() throws {
        // ArgumentParser only prints an error's `errorDescription`, so print all of an
        // ObfuscateError's messages ourselves.
        do {
            try generate()
        } catch let error as ObfuscateError {
            var standardError = StandardError()
            print("error: \(error.fullMessage)", to: &standardError)
            throw ExitCode.failure
        }
    }

    /// Encrypts every secret, then writes the generated `Secrets.swift` to the file (with `-f`) or stdout.
    ///
    /// The generated Swift goes to the file if one was given, otherwise to stdout. Everything else goes
    /// to stderr. With `--check`, the check runs first, so a failure never leaves output behind.
    ///
    /// - Throws: `ObfuscateError` if encryption fails, or `ExitCode.failure` if the check fails or the
    ///   file can't be written.
    func generate() throws {
        let secrets = try allSecrets()
        var properties: [String] = []
        var checks: [(secret: NamedSecret, encrypted: EncryptedSecret)] = []
        for secret in secrets {
            let encrypted = try SecretCipher.encrypt(secret.value)
            properties.append(GeneratedSource.property(for: secret, encrypted: encrypted))
            checks.append((secret, encrypted))
        }
        let outputString = GeneratedSource.file(properties: properties, propertyNames: secrets.map(\.name))

        var standardError = StandardError()

        if check {
            try verifyRoundTrip(checks)
        }

        guard let fileName else {
            // The source already ends with a newline.
            print(outputString, terminator: "")
            return
        }

        let path = fileName.hasSuffix(".swift") ? fileName : fileName + ".swift"
        do {
            try outputString.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("error: Unable to write to \(path): \(error.localizedDescription)", to: &standardError)
            throw ExitCode.failure
        }
        print("Saved to \(path)", to: &standardError)
    }

    /// Checks that every secret decodes back to its original value, reporting a pass or fail
    /// for each on stderr.
    ///
    /// Only the property names are reported. The secrets and decoded values are never printed,
    /// so they don't end up in terminal scrollback or screen shares.
    ///
    /// - Parameter checks: Each secret, with the encrypted form that the generated file will contain.
    /// - Throws: `ExitCode.failure` if any secret fails to decode correctly.
    func verifyRoundTrip(_ checks: [(secret: NamedSecret, encrypted: EncryptedSecret)]) throws {
        var standardError = StandardError()
        let results = checks.map { RoundTripResult(checking: $0.secret, encrypted: $0.encrypted) }

        for result in results {
            print(result.report, to: &standardError)
        }

        guard results.allSatisfy(\.passed) else {
            print("error: Check failed, so no output was written.", to: &standardError)
            throw ExitCode.failure
        }
    }
}
