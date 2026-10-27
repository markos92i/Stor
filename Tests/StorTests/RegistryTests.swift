//
//  RegistryTests.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import SwiftUI
import Testing
@testable import Stor

@Suite("StorableRegistry")
@MainActor
struct RegistryTests {

    @Test("Two stores with the same key keep their own value")
    func storesDoNotShareAKey() {
        let disk = Stor(backend: MemoryStorage())
        let keychain = Stor(backend: MemoryStorage())
        let inDisk = StorableBackend<String>(key: "user.session.email", default: "", store: disk)
        let inKeychain = StorableBackend<String>(key: "user.session.email", default: "", store: keychain)

        inDisk.value = "disk@example.com"
        inKeychain.value = "keychain@example.com"

        #expect(inDisk.value == "disk@example.com")
        #expect(inKeychain.value == "keychain@example.com")
    }

    @Test("Two stores at the same location share the value")
    func sameLocationSharesTheValue() {
        let directory = FileManager.default.temporaryDirectory.appending(component: "registry-\(UUID().uuidString)")
        let first = StorableBackend<Int>(key: "count", default: 0, store: Stor(directory: directory))
        let second = StorableBackend<Int>(key: "count", default: 0, store: Stor(directory: directory))

        first.value = 3
        #expect(second.value == 3)
    }

    /// The case of a locked device: the first read can't reach the keychain.
    @Test("An unavailable value isn't cached: the next access reads it again")
    func unavailableIsReadAgain() {
        let backend = MemoryStorage()
        backend.put(Data(#""stored""#.utf8), for: "token")
        backend.available = false
        let token = StorableBackend<String>(key: "token", default: "", store: Stor(backend: backend))

        #expect(token.value == "")

        backend.available = true
        #expect(token.value == "stored")
    }

    @Test("An optional property reads the stored value the first time")
    func optionalPropertyHydrates() {
        let backend = MemoryStorage()
        backend.put(Data(#""stored""#.utf8), for: "token")
        let token = StorableBackend<String?>(key: "token", default: nil, store: Stor(backend: backend))

        #expect(token.value == "stored")
    }

    @Test("A cached nil is kept: an optional property removed stays nil")
    func cachedNilIsKept() {
        let backend = MemoryStorage()
        backend.put(Data(#""stored""#.utf8), for: "token")
        let token = StorableBackend<String?>(key: "token", default: nil, store: Stor(backend: backend))

        token.value = nil
        #expect(token.value == nil)
    }

    @Test("A missing value is cached with its default")
    func missingIsCached() {
        let backend = MemoryStorage()
        let token = StorableBackend<String>(key: "token", default: "none", store: Stor(backend: backend))

        #expect(token.value == "none")
        backend.put(Data(#""late""#.utf8), for: "token")
        #expect(token.value == "none", "a value written behind Stor's back isn't seen")
    }

    @Test("A programmatic write reaches the property")
    func programmaticWriteReachesTheProperty() async {
        let backend = MemoryStorage()
        backend.writeDelay = PendingWritesTests.writeDelay
        let store = Stor(backend: backend)
        let count = StorableBackend<Int>(key: "count", default: 0, store: store)
        #expect(count.value == 0)

        // The registry subscribes in the background: keep writing until a write reaches it.
        let reached = await waitUntil(upTo: PendingWritesTests.writeLimit * 2) { @MainActor in
            await store.set("count", 5)
            return count.value == 5
        }
        #expect(reached)
    }

    @Test("The binding reads and writes the property")
    func bindingReadsAndWrites() {
        let flag = StorableBackend<Bool>(key: "flag", default: false, store: Stor(backend: MemoryStorage()))
        let binding: Binding<Bool> = flag.binding

        binding.wrappedValue = true

        #expect(flag.value)
        #expect(binding.wrappedValue)
    }
}

// MARK: - Macro usage (compile-time checks)

private extension Stor {
    static let probe = Stor(backend: MemoryStorage())
}

private extension KeychainStore {
    static let probe = KeychainStore(accessGroup: "probe")
}

/// `$property` exists for both macros, as with a property wrapper.
private struct MacroUsage: View {
    @Storable("probe.flag", store: .probe) var flag: Bool = false
    @Keychain("probe.secret", store: .probe) var secret: String?

    var body: some View {
        Toggle("flag", isOn: $flag)
        TextField("secret", text: Binding($secret) ?? .constant(""))
    }
}
