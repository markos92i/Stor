//
//  PendingWritesTests.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import Testing
@testable import Stor

/// A write through a property is recorded at once and persisted in the background.
@Suite("Pending writes")
struct PendingWritesTests {

    /// The backend takes this long per write, so a read right after the write finds it pending.
    static let writeDelay = Duration.milliseconds(200)
    /// The longest a background write may legitimately take.
    static let writeLimit = writeDelay * timingMargin

    private func slowStore() -> (Stor, MemoryStorage) {
        let backend = MemoryStorage()
        backend.writeDelay = Self.writeDelay
        return (Stor(backend: backend), backend)
    }

    @Test("A read from another thread sees a write the backend doesn't have yet")
    func offMainReadSeesThePendingWrite() async {
        let (store, backend) = slowStore()
        let token = StorableBackend<String>(key: "token", default: "", store: store)

        token.value = "new"
        let read = await Task.detached { token.value }.value

        #expect(read == "new")
        #expect(backend.stored("token") == nil, "the backend must still be writing")
    }

    @Test("A read from another thread sees a write made on the main actor")
    @MainActor
    func offMainReadSeesAMainActorWrite() async {
        let (store, _) = slowStore()
        let token = StorableBackend<String>(key: "token", default: "", store: store)

        token.value = "from main"
        let read = await Task.detached { token.value }.value

        #expect(read == "from main")
    }

    @Test("Programmatic get sees a property write that isn't persisted yet")
    func getSeesThePendingWrite() async {
        let (store, _) = slowStore()
        StorableBackend<Int>(key: "count", default: 0, store: store).value = 7
        #expect(await store.get("count") == 7)
    }

    @Test("set returns once its value is in the backend, also behind a slower write")
    func setWaitsForTheQueuedWrite() async {
        let (store, backend) = slowStore()
        StorableBackend<Int>(key: "count", default: 0, store: store).value = 1
        await store.set("count", 2)
        #expect(backend.stored("count") == Data("2".utf8))
    }

    @Test("Rapid writes land in order: the backend ends with the last one")
    func rapidWritesLandInOrder() async {
        let (store, backend) = slowStore()
        let count = StorableBackend<Int>(key: "count", default: 0, store: store)

        for value in 1..<20 { count.value = value }
        await store.set("count", 20)

        #expect(backend.stored("count") == Data("20".utf8))
        #expect(backend.writes < 20, "superseded writes are skipped")
    }

    @Test("Writing nil to an optional property removes the key")
    func nilRemoves() async {
        let (store, backend) = slowStore()
        await store.set("token", "abc")
        let token = StorableBackend<String?>(key: "token", default: nil, store: store)

        token.value = nil

        #expect(await (store.get("token") as String?) == nil)
        #expect(await waitUntil(upTo: Self.writeLimit) { backend.stored("token") == nil })
    }

    @Test("A purge drops pending writes: nothing comes back after it")
    func purgeDropsPendingWrites() async throws {
        let (store, backend) = slowStore()
        StorableBackend<String>(key: "token", default: "", store: store).value = "secret"

        await store.purge()
        try await Task.sleep(for: Self.writeLimit)   // longer than any write that could still land

        #expect(backend.stored("token") == nil)
        #expect(await (store.get("token") as String?) == nil)
    }
}
