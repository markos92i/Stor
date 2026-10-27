//
//  KeychainFormatTests.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import Testing
@testable import Stor

/// The bytes DynamicKeychain wrote must read back the same with the keychain coder: users keep
/// their session after updating. The real keychain is tested in the app's test target.
@Suite("Keychain format")
struct KeychainFormatTests {

    enum RawInt: Int { case one = 10_000_000, two = 20_000_000 }
    enum RawString: String { case one, two }

    private func decode<T>(_ data: Data, as type: T.Type) -> T? {
        StorableCoder.decode(data, as: type, using: JSONDecoder(), codableFirst: true)
    }

    private func encode<T>(_ value: T) -> Data? {
        StorableCoder.encode(value, with: JSONEncoder(), codableFirst: true)
    }

    @Test("Strings, numbers and booleans are JSON")
    func scalarsAreJSON() {
        #expect(decode(Data(#""abc""#.utf8), as: String.self) == "abc")
        #expect(decode(Data(#""abc""#.utf8), as: String?.self) == "abc")
        #expect(decode(Data("42".utf8), as: Int.self) == 42)
        #expect(decode(Data("3.5".utf8), as: Double.self) == 3.5)
        #expect(decode(Data("true".utf8), as: Bool.self) == true)
        #expect(encode("abc") == Data(#""abc""#.utf8))
        #expect(encode(42) == Data("42".utf8))
        #expect(encode(true) == Data("true".utf8))
    }

    @Test("Data is base64 JSON, not raw bytes")
    func dataIsBase64JSON() {
        let bytes = Data([1, 2, 3])
        #expect(encode(bytes) == Data(#""AQID""#.utf8))
        #expect(decode(Data(#""AQID""#.utf8), as: Data.self) == bytes)
        #expect(decode(Data(#""AQID""#.utf8), as: Data?.self) == bytes)
    }

    @Test("Dates use JSONEncoder's default strategy")
    func datesUseTheDefaultStrategy() throws {
        let date = Date(timeIntervalSince1970: 100)
        let written = try JSONEncoder().encode(date)
        #expect(encode(date) == written)
        #expect(decode(written, as: Date.self) == date)
    }

    @Test("Enums that aren't Codable keep their raw value: Int as bytes, String as UTF-8")
    func rawRepresentablesKeepTheirRawValue() {
        let intBytes = withUnsafeBytes(of: RawInt.two.rawValue) { Data($0) }
        #expect(encode(RawInt.two) == intBytes)
        #expect(decode(intBytes, as: RawInt.self) == .two)
        #expect(decode(intBytes, as: RawInt?.self) == .two)
        #expect(encode(RawString.two) == Data("two".utf8))
        #expect(decode(Data("two".utf8), as: RawString.self) == .two)
        #expect(decode(Data("two".utf8), as: RawString?.self) == .two)
    }

    @Test("A disk store still keeps Data as raw bytes")
    func diskKeepsRawData() {
        let bytes = Data([1, 2, 3])
        #expect(StorableCoder.encode(bytes, with: JSONEncoder()) == bytes)
        #expect(StorableCoder.decode(bytes, as: Data.self, using: JSONDecoder()) == bytes)
    }

    @Test("A disk store also keeps enums that aren't Codable")
    func diskStoresRawRepresentables() async {
        let store = Stor(backend: MemoryStorage())
        await store.set("level", RawInt.one)
        #expect(await store.get("level") == RawInt.one)
    }

    @Test("The keychain store's location names its service, group and accessibility")
    func keychainLocation() {
        let storage = KeychainStorage(service: "es.app", accessibility: .afterFirstUnlock, accessGroup: "TEAM.group")
        #expect(storage.location == "keychain:es.app|TEAM.group|afterFirstUnlock")
        #expect(KeychainStore(accessGroup: "TEAM.group").stor.location != KeychainStore.shared.stor.location)
        #expect(KeychainStore.shared.stor.codableFirst, "the keychain store writes DynamicKeychain's format")
    }
}
