//
//  ReadmeExamplesTests.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import Logy
import SwiftUI
import Synchronization
import Testing
import Stor

/// The README's examples, so they keep compiling. Nothing here touches the real keychain.
enum ReadmeExamples {
    struct ProfileDto: Codable, Sendable { var name: String }

    struct Defaults {
        static let shared = Defaults()

        @Storable("user.profile", store: .readme) var profile: ProfileDto?
        @Storable("app.counter", store: .readme) var counter: Int = 0
        @Keychain("user.session.accessToken", store: .group) var accessToken: String = ""
        @Keychain("user.session.refreshToken", store: .group) var refreshToken: String?
    }

    struct CounterView: View {
        @Storable("app.counter", store: .readme) var counter: Int = 0

        var body: some View {
            Stepper("\(counter)", value: $counter)
        }
    }

    struct Shared {
        @Keychain("sharedToken", store: .group) var sharedToken: String?
    }

    actor MemoryStorage: StorageBackend {
        nonisolated let location = "memory"
        private nonisolated let values = Mutex<[String: Data]>([:])

        func write(_ data: Data, for key: String) { values.withLock { $0[key] = data } }
        func read(_ key: String) -> Data? { values.withLock { $0[key] } }
        func readAll() -> [String: Data] { values.withLock { $0 } }
        func remove(_ key: String) { values.withLock { _ = $0.removeValue(forKey: key) } }
        func removeAll() { values.withLock { $0.removeAll() } }
        func allKeys() -> [String] { values.withLock { Array($0.keys) } }

        nonisolated func readSync(_ key: String) -> ReadResult {
            values.withLock { $0[key] }.map(ReadResult.found) ?? .missing
        }
    }

    struct Draft {
        @Storable("draft", store: .memory) var draft: String = ""
    }

    static func programmatic(_ profile: ProfileDto, token: String) async {
        await Stor.readme.set("user.profile", profile)
        let _: ProfileDto? = await Stor.readme.get("user.profile")
        await Stor.readme.remove("user.profile")
        _ = await Stor.readme.subscribe("user.profile") { (_: ProfileDto?) in }
        LogSubsystem.stor.level = .debug
    }
}

extension Stor {
    static let readme = Stor(backend: ReadmeExamples.MemoryStorage())
    static let memory = Stor(backend: ReadmeExamples.MemoryStorage())
}

extension KeychainStore {
    static let group = KeychainStore(accessibility: .afterFirstUnlock, accessGroup: "ABCDE12345.com.example.shared")
}

@Suite("README examples")
struct ReadmeExamplesTests {
    @Test func theCustomBackendRoundTrips() async {
        let draft = ReadmeExamples.Draft()
        draft.draft = "hello"
        #expect(draft.draft == "hello")
        #expect(await Stor.memory.get("draft") == "hello")
    }
}
