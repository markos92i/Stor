# DynamicStorable

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-007AFF)
![SPM](https://img.shields.io/badge/SPM-Compatible-blue)
![No Dependencies](https://img.shields.io/badge/Dependencies-None-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

A property wrapper that persists values to the app's documents directory with automatic SwiftUI view invalidation. Like `@AppStorage`, but for any `Codable` type — arrays, custom models, images, raw data — stored as files on disk.

## Features

- **`@Storable` property wrapper** — Declare, persist, and bind in one line
- **SwiftUI reactive** — Views re-render automatically when values change
- **Cross-view sync** — All `@Storable` instances for the same key share a single cache
- **Supports any `Codable`** — Arrays, structs, enums, nested types
- **Raw types** — `Data` and `UIImage` stored without JSON encoding
- **Optional & non-optional** — Both patterns supported
- **Atomic writes** — Disk persistence uses `.atomic` option
- **Zero dependencies** — Pure Swift + Foundation

## Installation

Add DynamicStorable to your project via Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/markos92i/DynamicStorable.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repository URL.

## Quick Start

```swift
import DynamicStorable

struct SearchView: View {
    @Storable("user.search.history") var history: [String] = []

    var body: some View {
        List(history, id: \.self) { term in
            Text(term)
        }
    }
}
```

## Usage

### Basic (non-optional with default)

```swift
@Storable("app.onboarding.completed") var onboardingDone: Bool = false
@Storable("user.search.history") var history: [SearchDto] = []
@Storable("user.preferences") var preferences: UserPreferences = .default
```

### Optional values

```swift
@Storable("user.profile") var profile: ProfileDto?
@Storable("cached.response") var cachedData: Data?
```

### UIImage storage

```swift
@Storable("user.avatar") var avatar: UIImage = UIImage()

// Optional image
@Storable("user.background") var background: UIImage?
```

### Two-way binding in SwiftUI

```swift
struct SettingsView: View {
    @Storable("app.theme") var theme: AppTheme = .system

    var body: some View {
        Picker("Theme", selection: $theme) {
            Text("System").tag(AppTheme.system)
            Text("Light").tag(AppTheme.light)
            Text("Dark").tag(AppTheme.dark)
        }
    }
}
```

### Cross-view synchronization

All `@Storable` instances with the same key share a single in-memory cache. When one writes, all others see the update on the next SwiftUI render pass:

```swift
// In ViewModel
@Storable("cart.items") var cartItems: [CartItem] = []

// In BadgeView (different view, same key)
@Storable("cart.items") var cartItems: [CartItem] = []
// → Always shows the current count
```

## How It Works

```
Write flow:
@Storable set → StorableStore.cache[key] = value → persist to disk (atomic)
                                                 → version += 1

Read flow:
@Storable get → StorableStore.cache[key] ?? @State fallback

Hydration (first access):
init → cache[key] ?? load from disk → populate cache → @State
```

- **In-memory cache** (`StorableStore.shared`) is the source of truth at runtime
- **Disk** provides persistence across launches
- **`@State`** provides SwiftUI observation for view invalidation

## Supported Types

| Type | Storage |
|------|---------|
| Any `Codable` | JSON encoded |
| `Data` | Raw bytes |
| `UIImage` | PNG data |
| `Optional<T>` | All above, nullable |

## Requirements

| Requirement | Version |
|------------|---------|
| Swift | 6.3+ |
| iOS | 18.0+ |
| macOS | 15.0+ |
| Xcode | 26+ |

## License

DynamicStorable is available under the MIT license. See the [LICENSE](LICENSE) file for details.
