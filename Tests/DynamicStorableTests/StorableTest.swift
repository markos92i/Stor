//
//  StorableTest.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 25/1/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation
import UIKit
import Testing
@testable import DynamicStorable

@Suite
struct StorableTest {
    struct CodableTest: Codable, Equatable {
        var name: String
        var value: Int
    }

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for url in files ?? [] where url.lastPathComponent.hasPrefix("test.") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Codable

    @Test func optionalCodable() async throws {
        @Storable("test.optional.codable") var value: CodableTest?

        value = .init(name: "Hello", value: 42)
        #expect(value?.name == "Hello")
        #expect(value?.value == 42)

        value = nil
        #expect(value == nil)
    }

    @Test func defaultCodable() async throws {
        @Storable("test.default.codable") var value: CodableTest = .init(name: "Default", value: 0)
        #expect(value.name == "Default")

        value = .init(name: "Updated", value: 99)
        #expect(value.name == "Updated")
        #expect(value.value == 99)
    }

    // MARK: - Data

    @Test func optionalData() async throws {
        @Storable("test.optional.data") var value: Data?

        let testData = Data([0x01, 0x02, 0x03, 0x04])
        value = testData
        #expect(value == testData)

        value = nil
        #expect(value == nil)
    }

    @Test func defaultData() async throws {
        let initial = Data([0xAA, 0xBB])
        @Storable("test.default.data") var value: Data = initial
        #expect(value == initial)

        let updated = Data([0xCC, 0xDD, 0xEE])
        value = updated
        #expect(value == updated)
    }

    // MARK: - UIImage

    @Test func optionalImage() async throws {
        @Storable("test.optional.image") var value: UIImage?

        let image = UIImage(systemName: "star.fill")!
        value = image
        #expect(value != nil)
        #expect(value!.size.width > 0)

        value = nil
        #expect(value == nil)
    }

    // MARK: - Persistence

    @Test func persistsAcrossReads() async throws {
        let stored = CodableTest(name: "Persist", value: 123)

        do {
            @Storable("test.persist") var value: CodableTest?
            value = stored
        }

        do {
            @Storable("test.persist") var value: CodableTest?
            #expect(value?.name == "Persist")
            #expect(value?.value == 123)
        }
    }
}
