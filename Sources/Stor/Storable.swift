//
//  Storable.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

// MARK: - @Storable Macro Declaration

/// Persists a property using `Stor` with automatic SwiftUI reactivity.
///
/// Apply to properties inside `@Observable @MainActor` classes:
///
/// ```swift
/// @Observable @MainActor
/// final class Settings {
///     @Storable("theme") var theme: Theme = .system
///     @Storable("token") var token: String?
///     @Storable("count", store: .custom) var count: Int = 0
/// }
/// ```
///
/// The macro expands to:
/// - A backing `StorableBackend<T>` property marked `@ObservationIgnored`
/// - Computed accessors that integrate with `@Observable`'s `access`/`withMutation`
///
/// ## Requirements
/// - The containing type must be `@Observable` for reactivity
/// - The containing type should be `@MainActor` for thread safety with SwiftUI
/// - Properties must have explicit type annotations
/// - Non-optional types require a default value
///
/// ## Thread Safety
/// `StorableBackend` uses `Mutex` for thread-safe value access.
/// Persistence happens asynchronously via `Stor`.
///
/// ## Cross-Instance Reactivity
/// Changes from other instances (or external processes) are automatically
/// picked up via `Stor` subscriptions. The `@Observable` class will
/// update its observers when external changes arrive.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro Storable(_ key: String, store: Stor = .shared) = #externalMacro(module: "StorMacros", type: "StorableMacro")
