//
/*
Project: obfuscate
File: main

Created by Paul Darcey on 3/11/2025

© 2025 Xerodonia Pty Ltd. All rights reserved
 
---------------------------------------------------- */

import Foundation
import ArgumentParser

/// CLI command `obfuscate` to create a Swift file you can use in an app that obfuscates the input.
/// Typically, the input is an API secret key.
///
/// The command will print the output to the console or, optionally, to a file in the cwd
///
/// You then have a file that produces a `Secrets` enum, which allows you to retrieve the original API key
/// without having the key anywhere in your source control system. It is also not directly within the `Secrets` file.
///
/// - Note: Each time the command is run, it will produce different output, because it generates a random seed for the
/// encoding/decoding process.
///
/// - Note: This method of obfuscating secrets was based on a blog post at [NSHipster](https://nshipster.com/secrets/)
///
/// - Important: This is **not** high-tech encryption. It's merely obfuscation. If *anyone* wants to crack this, it's
/// trivially easy to do so. It just means they have to be motivated enough to do *some* work, rather than have the keys in plain sight.
@main
struct Obfuscate: ParsableCommand {
    /// Flag to run a check that the output file will decode the input correctly
    @Flag(name: .shortAndLong, help: "Run the decode function and print the result. Should equal the API input.")
    var check = false
    
    /// You can optionally write the output to a file, so you can import it into your app
    @Option(name: .shortAndLong, help: "The file to output to. [Will add .swift, if necessary]")
    var fileName: String? = nil
    
    /// The secret you wish to obfuscate. Typically an API key
    @Argument(help: "The API you wish to obfuscate.")
    var api: String

    mutating func run() throws {
        // Set up random salt
        let salt = UInt64.random(in: 0...UInt64.max)
        let saltBytes = int64ToBytes(salt)
        let saltString = saltBytes.map { x in
            "0x\(String(format:"%02X", x))"
        }.joined(separator: ", ")
        // Encode input API using salt
        let apiBytes = encode(api, secret: saltBytes)
        let apiString = apiBytes.map { x in
            "0x\(String(format:"%02X", x))"
        }.joined(separator: ", ")
        // Generate and print a Swift file to decode the API
        let outputString = """
        // Secrets.swift
        enum Secrets {
            private static let salt: [UInt8] = [
                \(saltString)
            ]
            
            static var apiKey: String {
                let encoded: [UInt8] = [
                    \(apiString)
                ]
            
                return decode(encoded, secret: salt)
            }
            
            static func decode(_ encoded: [UInt8], secret: [UInt8]) -> String {
                let decodedBytes = encoded.enumerated().map { index, byte in
                    byte ^ secret[index % secret.count]
                }
                
                return String(bytes: decodedBytes, encoding: .utf8) ?? ""
            }
        }
        """
        print(outputString)

        if let fileName {
            var newFileName = fileName
            if !fileName.hasSuffix(".swift") {
                newFileName = fileName + ".swift"
            }
            do {
                try outputString.write(toFile: newFileName, atomically: true, encoding: .utf8)
            } catch {
                print("Unable to write to \(newFileName). Error: \(error)")
            }
        }

        if check {
            let decoded = decode(apiBytes, secret: saltBytes)
            print("Decoding produces:\n\(decoded)")
            if decoded == api {
                print("✅ Encoding and decoding works!")
            } else {
                print("Fail!")
            }
        }
    }
    
    /// Convert a 64-bit integer (UInt64) to a series of bytes ([UInt8])
    /// - Parameter value: Any 64-bit integer. In this case, the random 64-bit integer seed value
    /// - Returns: A series of eight bytes
    func int64ToBytes(_ value: UInt64) -> [UInt8] {
        var int = value
        let byteCount = MemoryLayout<Int64>.size
        var bytes = [UInt8](repeating: 0, count: byteCount)

        // Copy the bytes of the integer into the array
        withUnsafeBytes(of: &int) { rawBuffer in
            for i in 0..<byteCount {
                bytes[i] = rawBuffer[i]
            }
        }
        return bytes
    }
    
    /// Simple XOR encoding of the clearText against the series of bytes
    /// - Parameters:
    ///   - clearText: Any plain text. In this case, the API key
    ///   - secret: A random 64-bit integer, converted to eight 8-bit integers/bytes
    /// - Returns: A series of bytes/8-bit integers
    func encode(_ clearText: String, secret: [UInt8]) -> [UInt8] {
        let bytes = Array(clearText.utf8)

        let encodedBytes = bytes.enumerated().map { index, byte in
            byte ^ secret[index % secret.count]
        }

        return encodedBytes
    }
    
    /// Converts encrypted bytes back into plain text
    /// - Parameters:
    ///   - encoded: The encoded series of bytes
    ///   - secret: A random 64-bit integer, converted to eight 8-bit integers/bytes
    /// - Returns: Plain text. In this case, the API key
    func decode(_ encoded: [UInt8], secret: [UInt8]) -> String {
        let decodedBytes = encoded.enumerated().map { index, byte in
            byte ^ secret[index % secret.count]
        }

        return String(bytes: decodedBytes, encoding: .utf8) ?? ""
    }
}
