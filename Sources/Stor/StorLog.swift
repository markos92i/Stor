//
//  StorLog.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import Logy

// MARK: - Subsystem and channels

extension LogSubsystem {
    /// Stor's logs (`com.stor`). `LogSubsystem.stor.level = .off` silences all of Stor.
    public static let stor = LogSubsystem("com.stor")
}

extension LogChannel {
    static let disk = LogChannel(.stor, "disk")
    static let keychain = LogChannel(.stor, "keychain")
    static let storage = LogChannel(.stor, "storage")
}

// MARK: - Store kind

/// Which backend a store writes to: picks the channel (category) of its entries.
enum StoreKind: Sendable {
    case disk, keychain, custom

    init(_ backend: any StorageBackend) {
        self = switch backend {
        case is DiskStorage: .disk
        case is KeychainStorage: .keychain
        default: .custom
        }
    }

    var channel: LogChannel {
        switch self {
        case .disk: .disk
        case .keychain: .keychain
        case .custom: .storage
        }
    }
}

// MARK: - Events

/// Values are never logged, only their size: they may be credentials or personal data.
enum StorLog: LogEntry {
    case read(key: String, store: StoreKind, bytes: Int?)
    case write(key: String, store: StoreKind, bytes: Int, elapsed: Duration)
    case remove(key: String, store: StoreKind)
    case purge(store: StoreKind, keys: Int)
    case unavailable(key: String, store: StoreKind, detail: String)
    case failed(key: String, store: StoreKind, step: String, detail: String)

    var level: LogLevel {
        switch self {
        case .read, .write, .remove: .debug
        case .purge: .info
        case .unavailable: .warning
        case .failed: .error
        }
    }

    var channel: LogChannel { store.channel }

    private var store: StoreKind {
        switch self {
        case .read(_, let store, _), .write(_, let store, _, _), .remove(_, let store),
             .purge(let store, _), .unavailable(_, let store, _), .failed(_, let store, _, _):
            store
        }
    }

    // 􀄌 arrow.right.square: comes into the app. 􀄊 arrow.left.square: goes to the store. 􀟕 key.
    @LogBuilder
    func lines(bodies: Bool) -> [String] {
        switch self {
        case .read(let key, _, let bytes):
            "􀄌 read\t􀟕 \(key)\t\(bytes?.byteFormatted ?? "􀓔")"
        case .write(let key, _, let bytes, let elapsed):
            "􀄊 write\t􀟕 \(key)\t\(bytes.byteFormatted)\t􀐫 \(elapsed.logFormatted)"
        case .remove(let key, _):
            "􀄊 remove\t􀟕 \(key)"
        case .purge(_, let keys):
            "􀄊 purge\t\(keys) keys"
        case .unavailable(let key, _, let detail):
            "􀇿 read\t􀟕 \(key)\tunavailable, read again on next access"
            "􀺾 \(detail)"
        case .failed(let key, _, let step, let detail):
            "􀇾 \(step)\t􀟕 \(key)"
            "􀺾 \(detail)"
        }
    }
}
