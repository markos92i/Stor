//
//  SubscriptionToken.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 19/07/2026.
//

import Foundation

// MARK: - SubscriptionToken

/// Cancellable token for `Stor.subscribe`. Cancels on dealloc.
public final class SubscriptionToken: Sendable {
    private let onCancel: @Sendable () -> Void

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel()
    }

    deinit {
        onCancel()
    }
}
