//
/*
Project: obfuscate
File: main

Created by Paul Darcey on 3/11/2025

© 2025 Xerodonia Pty Ltd. All rights reserved
 
---------------------------------------------------- */

import Foundation
import ArgumentParser

@main
struct Obfuscate: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Run the decode function and print the result. Should equal the API input.")
    var check = false

    @Option(name: .shortAndLong, help: "The file to output to. [Will add .swift, if necessary]")
    var fileName: String? = nil

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
        let apiBytes = encode(api, cipher: saltBytes)
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
            
                return decode(encoded, cipher: salt)
            }
            
            static func decode(_ encoded: [UInt8], cipher: [UInt8]) -> String {
                let decodedBytes = encoded.enumerated().map { index, byte in
                    byte ^ cipher[index % cipher.count]
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
            let decoded = decode(apiBytes, cipher: saltBytes)
            print("Decoding produces:\n\(decoded)")
            if decoded == api {
                print("✅ Encoding and decoding works!")
            } else {
                print("Fail!")
            }
        }
    }

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

    func encode(_ clearText: String, cipher: [UInt8]) -> [UInt8] {
        let bytes = Array(clearText.utf8)

        let encodedBytes = bytes.enumerated().map { index, byte in
            byte ^ cipher[index % cipher.count]
        }

        return encodedBytes
    }

    func decode(_ encoded: [UInt8], cipher: [UInt8]) -> String {
        let decodedBytes = encoded.enumerated().map { index, byte in
            byte ^ cipher[index % cipher.count]
        }

        return String(bytes: decodedBytes, encoding: .utf8) ?? ""
    }
}
