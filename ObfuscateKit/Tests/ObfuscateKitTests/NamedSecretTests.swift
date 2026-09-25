//
/*
 Project: obfuscate
 File: NamedSecretTests

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import ObfuscateKit
import Testing

/// Tests for parsing and naming secrets.
@Suite("NamedSecret")
struct NamedSecretTests {
    @Test("A plain secret gets a generated apiKey name")
    func generatedName() {
        let secret = NamedSecret(value: "sk-plain", number: 3)
        #expect(secret.name == "apiKey3")
        #expect(secret.value == "sk-plain")
        #expect(secret.hasGeneratedName)
    }

    @Test("--key name=secret splits at the first '='")
    func parsesNameAndSecret() throws {
        let secret = try NamedSecret(parsing: "stripe=pk=with==equals", position: 1)
        #expect(secret.name == "stripe")
        #expect(secret.value == "pk=with==equals")
        #expect(!secret.hasGeneratedName)
    }

    @Test("--key without '=' is rejected")
    func missingSeparator() {
        #expect(throws: InputError.missingSeparator(position: 2)) {
            try NamedSecret(parsing: "sk-no-name", position: 2)
        }
    }

    @Test("--key with an invalid name is rejected", arguments: ["1abc=x", "abc/def==", "has space=x", "héllo=x", "=x"])
    func invalidName(argument: String) {
        #expect(throws: InputError.invalidName(position: 1)) {
            try NamedSecret(parsing: argument, position: 1)
        }
    }

    @Test("--key with a reserved name is rejected", arguments: ["class=x", "decrypt=x", "ObfuscateError=x", "_=x"])
    func reservedName(argument: String) {
        let name = String(argument.prefix { $0 != "=" })
        #expect(throws: InputError.reservedName(position: 1, name: name)) {
            try NamedSecret(parsing: argument, position: 1)
        }
    }

    @Test("--key with an empty secret is rejected")
    func emptySecret() {
        #expect(throws: InputError.emptySecret(position: 4)) {
            try NamedSecret(parsing: "QWxhZGRp=", position: 4)
        }
    }

    @Test("Valid identifiers", arguments: ["a", "openAI", "_private", "key_2", "ABC123"])
    func validIdentifiers(name: String) {
        #expect(NamedSecret.isValidIdentifier(name))
    }

    @Test("Invalid identifiers", arguments: ["", "2fast", "a-b", "a.b", "naïve", "emoji🔑"])
    func invalidIdentifiers(name: String) {
        #expect(!NamedSecret.isValidIdentifier(name))
    }
}

/// Tests for building the full list of secrets from the command-line input.
@Suite("SecretList")
struct SecretListTests {
    @Test("Named secrets come first, then plain secrets numbered from 1")
    func ordering() throws {
        let secrets = try SecretList.make(named: ["openAI=sk-1", "stripe=pk-2"], plain: ["p1", "p2"])
        #expect(secrets.map(\.name) == ["openAI", "stripe", "apiKey1", "apiKey2"])
        #expect(secrets.map(\.value) == ["sk-1", "pk-2", "p1", "p2"])
    }

    @Test("No secrets at all is rejected")
    func noSecrets() {
        #expect(throws: InputError.noSecrets) {
            try SecretList.make(named: [], plain: [])
        }
    }

    @Test("Duplicate --key names are rejected")
    func duplicateNames() {
        #expect(throws: InputError.duplicateName("dup")) {
            try SecretList.make(named: ["dup=a", "dup=b"], plain: [])
        }
    }

    @Test("A --key name that clashes with a generated name is rejected")
    func clashWithGeneratedName() {
        #expect(throws: InputError.duplicateName("apiKey1")) {
            try SecretList.make(named: ["apiKey1=a"], plain: ["b"])
        }
    }

    @Test("A bad --key is reported by its position")
    func reportsPosition() {
        #expect(throws: InputError.missingSeparator(position: 2)) {
            try SecretList.make(named: ["good=a", "bad-secret"], plain: [])
        }
    }
}

/// Tests for the messages shown for bad input: they're part of the command-line contract.
@Suite("InputError")
struct InputErrorTests {
    @Test("Messages never include the secret")
    func messagesNeverIncludeSecrets() {
        let secret = "abc/defSECRET"
        for argument in ["\(secret)", "\(secret)==", "QWxh\(secret)=", "1\(secret)=x"] {
            do {
                _ = try NamedSecret(parsing: argument, position: 1)
                Issue.record("Expected '\(argument)' to be rejected")
            } catch {
                #expect(error.errorDescription?.contains(secret) == false)
            }
        }
    }

    @Test("Messages match the command-line contract")
    func messages() {
        #expect(InputError.missingSeparator(position: 1).errorDescription
                == "--key #1 must be in the form name=secret, but it has no '='.")
        #expect(InputError.reservedName(position: 2, name: "class").errorDescription
                == "--key #2: 'class' is reserved in Swift or in Secrets. Choose another name.")
        #expect(InputError.emptySecret(position: 3).errorDescription == "--key #3: the secret after '=' is empty.")
        #expect(InputError.noSecrets.errorDescription
                == "Provide at least one secret, either as an argument or with --key name=secret.")
        #expect(InputError.duplicateName("dup").errorDescription
                == "The name 'dup' is used more than once. Each secret needs its own name.")
    }

    @Test("Only errorDescription is used")
    func otherLocalizedErrorProperties() {
        let error = InputError.noSecrets
        #expect(error.failureReason == nil)
        #expect(error.recoverySuggestion == nil)
        #expect(error.helpAnchor == nil)
    }
}
