# Stor

![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-007AFF)
![Strict Concurrency](https://img.shields.io/badge/Concurrency-Strict-00B386)
![SPM](https://img.shields.io/badge/SPM-Compatible-blue)

Reactive persistence for SwiftUI: like `@AppStorage`, but for real objects, in a file or in the keychain.

## Features

- **`@Storable`**: a property persisted in a file (one per key, atomic writes).
- **`@Keychain`**: a property persisted in the keychain, with access groups and accessibility.
- **Reactive**: views reading a property refresh when it changes, also when the change comes from the programmatic API.
- **`$property`** binding for both, as with a property wrapper.
- **Programmatic API** (`Stor`, `KeychainStore`) from any actor or background task.
- **Codable, RawStorable or RawRepresentable** values; no extra conformance.
- **Pluggable backends**, strict concurrency, logs through [Logy](https://github.com/markos92i/Logy).

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/markos92i/Stor.git", from: "2.0.0")
]
```

## Quick start

```swift
import Stor

struct Defaults {
    static let shared = Defaults()

    @Storable("user.profile") var profile: ProfileDto?          // file
    @Storable("app.counter") var counter: Int = 0
    @Keychain("user.session.accessToken") var accessToken: String = ""   // keychain
    @Keychain("user.session.refreshToken") var refreshToken: String?
}

struct CounterView: View {
    @Storable("app.counter") var counter: Int = 0

    var body: some View {
        Stepper("\(counter)", value: $counter)
    }
}
```

- Non-optional properties need a default value; optional ones default to `nil`, and writing `nil` removes the key.
- The setter is `nonmutating`, so properties work in `static let` singletons. They don't work in classes.

## Keychain

`@Keychain` only accepts a `KeychainStore`, so a secret can't end up in a file by mistake:

```swift
extension KeychainStore {
    static let group = KeychainStore(accessibility: .afterFirstUnlock, accessGroup: "ABCDE12345.com.example.shared")
}

@Keychain("sharedToken", store: .group) var sharedToken: String?
```

- Each key is a generic password: service = bundle identifier, account = key, plus the access group.
- `KeychainStore()` defaults to `.whenUnlocked` and no access group.
- Values are JSON with `JSONEncoder`'s default strategies (`Data` as base64); enums that aren't Codable keep their raw value (`Int` as bytes, `String` as UTF-8). It's the format DynamicKeychain wrote, so items it saved are read as they are.
- A locked device (or any read error) is reported as unavailable and never cached: the next access reads the keychain again.
- Values are never logged, only their size.

## Programmatic access

```swift
await Stor.shared.set("user.profile", profile)            // @Storable("user.profile") views refresh
let profile: ProfileDto? = await Stor.shared.get("user.profile")
await Stor.shared.remove("user.profile")

await KeychainStore.shared.set("user.session.accessToken", token)
await KeychainStore.shared.remove(keys: ["access_token", "refresh_token"])
await KeychainStore.shared.purge()                        // logout
```

- `set` and `remove` return once the value is in the backend.
- `purge()` deletes everything in the store; `removeAll()` removes every key of a `Stor`.

## Writes and reads

- A write through a property is recorded at once and persisted in the background, so the setter never blocks on disk or keychain.
- A read from any thread sees the newest write, even one not persisted yet: on the main actor from the registry, elsewhere from the store (the pending write, else the backend).
- Writes to the same key land in order; a write superseded before it starts is skipped.
- A purge drops pending writes and waits for the ones in progress, so nothing comes back after it.
- Stores at the same location (same directory, same keychain service, group and accessibility) share their values; different stores with the same key don't.

## RawStorable

For types with a natural binary representation:

```swift
extension UIImage: RawStorable {
    public func toData() -> Data? { pngData() }
    public static func fromData(_ data: Data) -> Self? { Self(data: data) }
}
```

`UIImage` and `Data` conform out of the box. In a file, `Data` is stored as raw bytes.

## Subscriptions

```swift
let token = await Stor.shared.subscribe("user.profile") { (profile: ProfileDto?) in
    // runs on the main actor after each write or removal
}
// Hold `token`: the subscription ends on `cancel()` or when it's released.
```

## Logging

Stor logs through Logy: subsystem `com.stor`, categories `disk`, `keychain` and `storage` (custom backends). Reads, writes and removals are `.debug`, purges `.info`, unavailable reads `.warning`, failures `.error`.

```swift
import Logy

LogSubsystem.stor.level = .off
```

## Custom backend

```swift
import Synchronization

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

extension Stor {
    static let memory = Stor(backend: MemoryStorage())
}

@Storable("draft", store: .memory) var draft: String = ""
```

- `location` says where the values live: two stores at the same location share `@Storable` values.
- Return `.unavailable` from `readSync` when the value exists but can't be read now; it's read again on the next access.

## Testing

The keychain needs an app as test host (entitlements), so Stor's own tests cover the disk and an in-memory backend; the real keychain is tested from an app's test target.

## Architecture

```
Stor/
├── Stor.swift               Public actor: get/set/remove/purge/subscribe, pending writes
├── Storable.swift           @Storable and @Keychain macro declarations
├── StorableBackend.swift    What a property expands to: value and binding
├── StorableRegistry.swift   Observable cache per store location and key
├── StorageBackend.swift     Backend protocol and ReadResult
├── DiskStorage.swift        File backend
├── KeychainStorage.swift    Keychain backend
├── KeychainStore.swift      Keychain store for @Keychain and programmatic access
├── KeychainAccessibility.swift
├── RawStorable.swift        RawStorable and the runtime coder
├── StorLog.swift            Log events and channels
├── SubscriptionToken.swift
└── StorableError.swift
```

## Requirements

| Requirement | Version |
|---|---|
| Swift | 6.4+ |
| Xcode | 27+ |
| iOS | 18.0+ |
| macOS | 15.0+ |
