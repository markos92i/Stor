//
//  Timing.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation

/// How many times the worst legitimate duration a test waits before giving up.
let timingMargin = 3

/// Polls `condition` until it holds or `limit` passes; returns whether it held.
func waitUntil(upTo limit: Duration, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
