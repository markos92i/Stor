# Stor

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-007AFF)
![Strict Concurrency](https://img.shields.io/badge/Concurrency-Strict-00B386)
![SPM](https://img.shields.io/badge/SPM-Compatible-blue)

A reactive persistence library for iOS. Persists any `Codable` or binary type to disk and provides automatic SwiftUI view invalidation — like `@AppStorage` but for real objects.

## Features

- **`@Storable` property wrapper** — Reactive persistence in SwiftUI views. Reads are synchronous, writes persist automatically
- **`Stor.shared` programmatic API** — Read/write from any actor, ViewModel, or background context
- **Cross-context reactivity** — A write from `Stor.shared.set(...)` automatically refreshes all `@Storable` views with the same key
- **Unified API** — Same `set`/`get` for `Codable` (JSON) and `RawStorable` (binary) types
- **No extra conformance** — Your types only need `Codable` or `RawStorable`. Nothing else
- **Thread-safe** — Actor-isolated store, `Mutex`-protected observer, `@Observable` for SwiftUI
- **Strict concurrency compliant** — Zero warnings with `-strict-concurrency=complete`
- **Pluggable backends** — Default is disk (one file per key, atomic writes). Swap with in-memory for tests

## Installation

Add Stor via Swift Package Manager:

```swift
dependencies: [
    .package(path: "../Frameworks/Stor")
]
```

## Quick Start

### In a SwiftUI view

```swift
import Stor

struct ProfileView: View {
    @Storable("user.profile") var profile: ProfileDto?
    @Storable("user.avatar") var avatar: UIImage?
    @Storable("app.counter") var counter: Int = 0

    var body: some View {
        VStack {
            Text(profile?.name ?? "No user")
            Button("+1") { counter += 1 }
        }
    }
}
```

### From a ViewModel or any actor

```swift
@MainActor @Observable
final class ProfileViewModel {
    func updateProfile(_ profile: ProfileDto) async {
        await Stor.shared.set("user.profile", profile)
        // → all @Storable("user.profile") views refresh automatically
    }

    func updateAvatar(_ image: UIImage) async {
        await Stor.shared.set("user.avatar", image)
    }

    func clear() async {
        await Stor.shared.remove("user.profile")
    }
}
```

### Reading programmatically

```swift
let profile: ProfileDto? = await Stor.shared.get("user.profile")
let avatar: UIImage? = await Stor.shared.get("user.avatar")
```

## RawStorable (binary types)

For types that have a natural binary representation (not JSON):

```swift
extension UIImage: RawStorable {
    public func toData() -> Data? { pngData() }
    public static func fromData(_ data: Data) -> Self? { Self(data: data) }
}
```

`UIImage` conformance is included out of the box. Add your own for protobuf, MessagePack, etc.

## Subscriptions

Observe changes to a key from any context:

```swift
let token = await Stor.shared.subscribe("user.profile") { (profile: ProfileDto?) in
    print("Profile changed: \(profile?.name ?? "nil")")
}

// Hold `token` — subscription cancels on dealloc or `.cancel()`
```

## Lifecycle

```swift
// Remove a single key
await Stor.shared.remove("user.profile")

// Remove all keys
await Stor.shared.removeAll()

// Destroy all data (logout, app reset)
await Stor.shared.purge()
```

## Custom Backend (testing)

```swift
actor MemoryStorage: StorageBackend {
    private var store: [String: Data] = [:]

    func write(_ data: Data, for key: String) { store[key] = data }
    func read(_ key: String) -> Data? { store[key] }
    func readAll() -> [String: Data] { store }
    func remove(_ key: String) { store.removeValue(forKey: key) }
    func removeAll() { store.removeAll() }
    func allKeys() -> [String] { Array(store.keys) }
    nonisolated func readSync(_ key: String) -> Data? { nil }
}

let testStore = Stor(backend: MemoryStorage())
```

## Architecture

```
Stor/
├── Stor.swift           — Public actor: get/set/remove/subscribe
├── Storable.swift       — @Storable property wrapper + @Observable observer
├── RawStorable.swift    — RawStorable protocol + StorableCoder (runtime dispatch)
├── DiskStorage.swift    — Default file-system backend
├── StorageBackend.swift — Protocol for pluggable backends
├── SubscriptionToken.swift
└── StorableError.swift
```

## Requirements

| Requirement | Version |
|------------|---------|
| Swift | 6.3+ |
| iOS | 18.0+ |
| macOS | 15.0+ |
| Xcode | 26+ |
