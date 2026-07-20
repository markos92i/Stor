//
//  StorableTest.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 25/1/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Testing
@testable import Stor

// MARK: - Helpers

private func makeStore() -> Stor {
    let dir = FileManager.default.temporaryDirectory
        .appending(component: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
    return Stor(directory: dir)
}

private func makeStore(encoder: JSONEncoder? = nil, decoder: JSONDecoder? = nil) -> Stor {
    let dir = FileManager.default.temporaryDirectory
        .appending(component: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
    return Stor(directory: dir, encoder: encoder, decoder: decoder)
}

// MARK: - Stor Suite

@Suite("Stor + @Storable")
struct StorableTest {

    struct Item: Codable, Equatable {
        var name: String
        var value: Int
    }

    struct NestedItem: Codable, Equatable {
        var title: String
        var count: Int
        var child: Item?
        private enum CodingKeys: String, CodingKey {
            case title = "itemTitle"
            case count = "itemCount"
            case child = "childItem"
        }
    }

    struct TimestampedItem: Codable, Equatable {
        var name: String
        var createdAt: Date
    }

    enum Status: String, Codable, Equatable { case active, inactive, pending }
    struct StatusItem: Codable, Equatable { var id: Int; var status: Status }

    struct ItemV1: Codable, Equatable { var name: String; var value: Int }
    struct ItemV2: Codable, Equatable { var name: String; var value: Int; var extra: String? }

    // MARK: - Read / Write

    @Test("get returns nil for absent key")
    func getAbsent() async {
        let store = makeStore()
        let result: Item? = await store.get("missing")
        #expect(result == nil)
    }

    @Test("set and get round-trips a Codable value")
    func setAndGet() async {
        let store = makeStore()
        await store.set("item", Item(name: "Hello", value: 42))
        let result: Item? = await store.get("item")
        #expect(result == Item(name: "Hello", value: 42))
    }

    @Test("set optional nil removes the key")
    func setNilRemoves() async {
        let store = makeStore()
        await store.set("item", Item(name: "A", value: 1))
        await store.set("item", nil as Item?)
        #expect(await (store.get("item") as Item?) == nil)
    }

    @Test("remove deletes the key")
    func removeKey() async {
        let store = makeStore()
        await store.set("item", Item(name: "B", value: 2))
        await store.remove("item")
        #expect(await (store.get("item") as Item?) == nil)
    }

    @Test("removeAll clears all keys")
    func removeAllKeys() async {
        let store = makeStore()
        await store.set("a", Item(name: "A", value: 1))
        await store.set("b", Item(name: "B", value: 2))
        await store.removeAll()
        #expect(await (store.get("a") as Item?) == nil)
        #expect(await (store.get("b") as Item?) == nil)
    }

    @Test("multiple sets preserve last value")
    func multipleSetsSameKey() async {
        let store = makeStore()
        await store.set("item", Item(name: "First", value: 1))
        await store.set("item", Item(name: "Second", value: 2))
        await store.set("item", Item(name: "Third", value: 3))
        let result: Item? = await store.get("item")
        #expect(result?.name == "Third")
    }

    @Test("Data round-trips correctly")
    func dataRoundTrip() async {
        let store = makeStore()
        let data = Data([0x01, 0x02, 0x03, 0x04])
        await store.set("raw", data)
        #expect(await (store.get("raw") as Data?) == data)
    }

    @Test("independent keys do not interfere")
    func independentKeys() async {
        let store = makeStore()
        await store.set("x", Item(name: "X", value: 10))
        await store.set("y", Item(name: "Y", value: 20))
        #expect(await (store.get("x") as Item?)?.name == "X")
        #expect(await (store.get("y") as Item?)?.name == "Y")
    }

    // MARK: - Persistence

    @Test("persists to disk and reloads across instances")
    func persistsAcrossInstances() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(component: "persist-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = Stor(directory: dir)
        await store1.set("key", Item(name: "Persist", value: 123))

        let store2 = Stor(directory: dir)
        let result: Item? = await store2.get("key")
        #expect(result?.name == "Persist")
        #expect(result?.value == 123)
    }

    @Test("concurrent sets all land correctly")
    func concurrentSets() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(component: "concurrent-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = Stor(directory: dir)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                let i = i
                group.addTask { await store.set("key-\(i)", Item(name: "item", value: i)) }
            }
        }

        for i in 0..<100 {
            let result: Item? = await store.get("key-\(i)")
            #expect(result?.value == i)
        }
    }

    // MARK: - Subscriptions

    @Test("subscribe fires handler for the correct key")
    func subscriptionFiredForKey() async throws {
        let store = makeStore()
        let targetKey = "sub-target-\(UUID().uuidString)"

        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()

        let token = await store.subscribe(targetKey) { (_: Item?) in
            Task { await counter.increment() }
        }

        await store.set(targetKey, Item(name: "N", value: 1))
        try await Task.sleep(for: .milliseconds(100))
        _ = token  // keep alive

        #expect(await counter.count == 1)
    }

    @Test("subscribe does not fire for unrelated key")
    func subscriptionNotFiredForOtherKey() async throws {
        let store = makeStore()
        let watchedKey = "sub-watched-\(UUID().uuidString)"
        let otherKey = "sub-other-\(UUID().uuidString)"

        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()

        let token = await store.subscribe(watchedKey) { (_: Item?) in
            Task { await counter.increment() }
        }

        await store.set(otherKey, Item(name: "O", value: 2))
        try await Task.sleep(for: .milliseconds(100))
        _ = token

        #expect(await counter.count == 0)
    }

    @Test("subscribe receives decoded value")
    func subscriptionReceivesDecodedValue() async throws {
        let store = makeStore()
        let key = "sub-decoded-\(UUID().uuidString)"

        actor Received { var item: Item?; func set(_ v: Item?) { item = v } }
        let received = Received()

        let token = await store.subscribe(key) { (item: Item?) in
            Task { await received.set(item) }
        }

        let expected = Item(name: "Sub", value: 99)
        await store.set(key, expected)
        try await Task.sleep(for: .milliseconds(100))
        _ = token

        #expect(await received.item == expected)
    }

    @Test("subscribe receives nil on remove")
    func subscriptionReceivesNilOnRemove() async throws {
        let store = makeStore()
        let key = "sub-nil-\(UUID().uuidString)"
        await store.set(key, Item(name: "X", value: 1))

        actor Received { var item: Item? = Item(name: "initial", value: 0); func set(_ v: Item?) { item = v } }
        let received = Received()

        let token = await store.subscribe(key) { (item: Item?) in
            Task { await received.set(item) }
        }

        await store.remove(key)
        try await Task.sleep(for: .milliseconds(100))
        _ = token

        #expect(await received.item == nil)
    }

    @Test("token cancel stops subscription")
    func tokenCancelStopsSubscription() async throws {
        let store = makeStore()
        let key = "sub-cancel-\(UUID().uuidString)"

        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()

        let token = await store.subscribe(key) { (_: Item?) in
            Task { await counter.increment() }
        }

        await store.set(key, Item(name: "A", value: 1))
        try await Task.sleep(for: .milliseconds(50))

        token.cancel()
        try await Task.sleep(for: .milliseconds(50))

        await store.set(key, Item(name: "B", value: 2))
        try await Task.sleep(for: .milliseconds(100))

        // Only the first write should have been received.
        #expect(await counter.count == 1)
    }

    // MARK: - Date

    @Test("Date round-trips correctly via ISO8601 (default)")
    func dateRoundTripISO8601() async {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        await store.set("ts", TimestampedItem(name: "ts", createdAt: date))
        let result: TimestampedItem? = await store.get("ts")
        #expect(result?.createdAt.timeIntervalSince1970.rounded() == date.timeIntervalSince1970.rounded())
    }

    @Test("Date stored as ISO8601 string, not TimeInterval")
    func dateStoredAsISO8601String() async {
        let store = makeStore()
        await store.set("ts", TimestampedItem(name: "check", createdAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let json = await store.rawJSON(for: "ts")
        #expect(json?.contains("\"20") == true)
        #expect(json?.contains("1700000000") == false)
    }

    @Test("Date round-trips with custom Unix timestamp decoder")
    func dateRoundTripUnixTimestamp() async {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        let store = makeStore(encoder: enc, decoder: dec)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        await store.set("ts", TimestampedItem(name: "unix", createdAt: date))
        let result: TimestampedItem? = await store.get("ts")
        #expect(result?.createdAt.timeIntervalSince1970.rounded() == date.timeIntervalSince1970.rounded())
        let json = await store.rawJSON(for: "ts")
        #expect(json?.contains("1700000000") == true)
    }

    @Test("ISO8601 store cannot decode Unix timestamp data")
    func decoderMismatchFails() async {
        let unixEnc = JSONEncoder(); unixEnc.dateEncodingStrategy = .secondsSince1970
        let dir = FileManager.default.temporaryDirectory
            .appending(component: "store-mismatch-\(UUID().uuidString)", directoryHint: .isDirectory)
        let writeStore = Stor(directory: dir, encoder: unixEnc)
        await writeStore.set("ts", TimestampedItem(name: "mismatch", createdAt: Date(timeIntervalSince1970: 1_700_000_000)))

        // Same directory, default ISO8601 decoder — must fail gracefully.
        let readStore = Stor(directory: dir)
        #expect(await (readStore.get("ts") as TimestampedItem?) == nil)
    }

    // MARK: - Enum

    @Test("Enum with String rawValue round-trips correctly")
    func enumRoundTrip() async {
        let store = makeStore()
        await store.set("status", StatusItem(id: 1, status: .active))
        #expect(await (store.get("status") as StatusItem?)?.status == .active)
    }

    @Test("Enum survives unknown raw value gracefully")
    func enumUnknownValue() async {
        let store = makeStore()
        await store.setRaw("bad-status", #"{"id":1,"status":"unknown_value"}"#.data(using: .utf8)!)
        #expect(await (store.get("bad-status") as StatusItem?) == nil)
    }

    // MARK: - Nested / Arrays / Schema evolution

    @Test("Nested type with custom CodingKeys round-trips correctly")
    func nestedCodingKeys() async {
        let store = makeStore()
        let item = NestedItem(title: "parent", count: 3, child: .init(name: "child", value: 99))
        await store.set("nested", item)
        #expect(await (store.get("nested") as NestedItem?) == item)
    }

    @Test("Array round-trips correctly")
    func arrayRoundTrip() async {
        let store = makeStore()
        let items = [Item(name: "a", value: 1), Item(name: "b", value: 2)]
        await store.set("array", items)
        #expect(await (store.get("array") as [Item]?) == items)
    }

    @Test("Empty array round-trips correctly")
    func emptyArrayRoundTrip() async {
        let store = makeStore()
        await store.set("empty", [Item]())
        #expect(await (store.get("empty") as [Item]?) == [])
    }

    @Test("V2 model decodes V1 data — new optional field defaults to nil")
    func backwardCompatibility() async {
        let store = makeStore()
        await store.set("model", ItemV1(name: "legacy", value: 42))
        let result: ItemV2? = await store.get("model")
        #expect(result?.name == "legacy")
        #expect(result?.extra == nil)
    }

    // MARK: - Resilience

    @Test("Corrupted JSON returns nil, does not crash")
    func corruptedJSON() async {
        let store = makeStore()
        await store.setRaw("corrupt", "not valid json {{{}".data(using: .utf8)!)
        #expect(await (store.get("corrupt") as Item?) == nil)
    }

    @Test("Wrong type returns nil, does not crash")
    func wrongType() async {
        let store = makeStore()
        await store.set("typed", Item(name: "x", value: 1))
        #expect(await (store.get("typed") as TimestampedItem?) == nil)
    }

    @Test("Absent key returns nil without crashing")
    func absentKeyReturnsNil() async {
        #expect(await (makeStore().get("nope") as Item?) == nil)
    }

    @Test("Corrupt store directory hydrates empty, does not crash")
    func corruptStoreDirectory() async throws {
        let fakeDir = FileManager.default.temporaryDirectory
            .appending(component: "fake-store-\(UUID().uuidString)")
        try "not a directory".write(to: fakeDir, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fakeDir) }
        let store = Stor(directory: fakeDir)
        #expect(await (store.get("any") as Item?) == nil)
    }

    // MARK: - UIImage

    #if canImport(UIKit)
    @Test("UIImage stores and retrieves as PNG")
    func imageRoundTrip() async {
        let store = makeStore()
        let image = UIImage(systemName: "star.fill")!
        await store.set("img", image)
        let result: UIImage? = await store.get("img")
        #expect(result != nil)
        #expect(result!.size.width > 0)
    }

    @Test("UIImage nil removes key")
    func imageNilRemoves() async {
        let store = makeStore()
        await store.set("img", UIImage(systemName: "star.fill")!)
        await store.set("img", nil as UIImage?)
        #expect(await (store.get("img") as UIImage?) == nil)
    }
    #endif
}

// MARK: - @Storable reactivity simulation

/// Verifica el contrato de reactividad de @Storable usando subscribe() directamente.
/// Es equivalente a lo que StorableObserver hace internamente para invalidar vistas SwiftUI.
@Suite("@Storable reactivity via subscribe")
struct StorableReactivityTest {

    struct Profile: Codable, Equatable {
        var name: String
        var age: Int
    }

    @Test("ViewModel write via Stor updates subscriber")
    func viewModelWriteUpdatesSubscriber() async throws {
        let store = makeStore()
        let key = "profile-\(UUID().uuidString)"

        actor Cache { var value: Profile?; func set(_ v: Profile?) { value = v } }
        let cache = Cache()

        // Simulate what StorableObserver does: subscribe and update local state.
        let token = await store.subscribe(key) { (p: Profile?) in
            Task { await cache.set(p) }
        }

        let newProfile = Profile(name: "Marcos", age: 32)
        await store.set(key, newProfile)
        try await Task.sleep(for: .milliseconds(100))
        _ = token

        #expect(await cache.value == newProfile)
    }

    @Test("Multiple sequential writes all reach subscriber in order")
    func multipleWritesReachSubscriber() async throws {
        let store = makeStore()
        let key = "profile-multi-\(UUID().uuidString)"

        actor History { var names: [String] = []; func append(_ n: String) { names.append(n) } }
        let history = History()

        let token = await store.subscribe(key) { (p: Profile?) in
            if let p { Task { await history.append(p.name) } }
        }

        await store.set(key, Profile(name: "First", age: 1))
        try await Task.sleep(for: .milliseconds(30))
        await store.set(key, Profile(name: "Second", age: 2))
        try await Task.sleep(for: .milliseconds(30))
        await store.set(key, Profile(name: "Third", age: 3))
        try await Task.sleep(for: .milliseconds(100))
        _ = token

        #expect(await history.names == ["First", "Second", "Third"])
    }

    @Test("Two subscribers on same key both receive the write")
    func twoSubscribersOnSameKey() async throws {
        let store = makeStore()
        let key = "profile-cross-\(UUID().uuidString)"

        actor Consumer { var value: Profile?; func set(_ v: Profile?) { value = v } }
        let consumerA = Consumer()
        let consumerB = Consumer()

        let tokenA = await store.subscribe(key) { (p: Profile?) in
            Task { await consumerA.set(p) }
        }
        let tokenB = await store.subscribe(key) { (p: Profile?) in
            Task { await consumerB.set(p) }
        }

        await store.set(key, Profile(name: "Shared", age: 10))
        try await Task.sleep(for: .milliseconds(100))
        _ = tokenA; _ = tokenB

        #expect(await consumerA.value?.name == "Shared")
        #expect(await consumerB.value?.name == "Shared", "Both subscribers must receive the write")
    }

    @Test("Subscriber receives nil when key is removed")
    func subscriberReceivesNilOnRemove() async throws {
        let store = makeStore()
        let key = "profile-remove-\(UUID().uuidString)"
        await store.set(key, Profile(name: "Existing", age: 1))

        actor Cache {
            var value: Profile? = Profile(name: "initial", age: 0)
            func set(_ v: Profile?) { value = v }
        }
        let cache = Cache()

        let token = await store.subscribe(key) { (p: Profile?) in
            Task { await cache.set(p) }
        }

        await store.remove(key)
        try await Task.sleep(for: .milliseconds(100))
        _ = token

        #expect(await cache.value == nil)
    }
}
