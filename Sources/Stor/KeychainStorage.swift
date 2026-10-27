//
//  KeychainStorage.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import Logy

// MARK: - KeychainStorage

/// Keychain-backed `StorageBackend`: one generic password per key (`service` + `account` = key).
/// The queries match DynamicKeychain's, so items it saved are read as they are.
public actor KeychainStorage: StorageBackend {

    public nonisolated let service: String
    public nonisolated let accessibility: KeychainAccessibility
    public nonisolated let accessGroup: String?
    private nonisolated let log = Logy<StorLog>()

    public init(
        service: String = Bundle.main.bundleIdentifier ?? "Stor",
        accessibility: KeychainAccessibility = .whenUnlocked,
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessibility = accessibility
        self.accessGroup = accessGroup
    }

    public nonisolated var location: String {
        "keychain:\(service)|\(accessGroup ?? "")|\(accessibility)"
    }

    // MARK: - StorageBackend

    public func write(_ data: Data, for key: String) {
        var item = query(key, accessible: true)
        item[kSecValueData as String] = data
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let changes = [kSecValueData as String: data]
            status = SecItemUpdate(query(key, accessible: true) as CFDictionary, changes as CFDictionary)
        }
        if status != errSecSuccess {
            log.log(.failed(key: key, store: .keychain, step: "write", detail: Self.describe(status)))
        }
    }

    public func read(_ key: String) -> Data? {
        if case .found(let data) = readSync(key) { data } else { nil }
    }

    public func readAll() -> [String: Data] {
        allKeys().reduce(into: [:]) { result, key in
            if let data = read(key) { result[key] = data }
        }
    }

    public func allKeys() -> [String] {
        var search = query(nil, accessible: false)
        search[kSecReturnAttributes as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status != errSecItemNotFound {
                log.log(.failed(key: "*", store: .keychain, step: "list", detail: Self.describe(status)))
            }
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    public func remove(_ key: String) {
        let status = SecItemDelete(query(key, accessible: false) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            log.log(.failed(key: key, store: .keychain, step: "remove", detail: Self.describe(status)))
        }
    }

    public func removeAll() {
        let status = SecItemDelete(query(nil, accessible: false) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            log.log(.failed(key: "*", store: .keychain, step: "remove all", detail: Self.describe(status)))
        }
    }

    /// Anything but "found" or "not found" (a locked device, a missing entitlement) is `unavailable`.
    public nonisolated func readSync(_ key: String) -> ReadResult {
        var search = query(key, accessible: true)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .missing }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            log.log(.unavailable(key: key, store: .keychain, detail: Self.describe(status)))
            return .unavailable
        }
    }

    // MARK: - Queries

    /// Reads and writes filter by accessibility, deletes don't: the same queries DynamicKeychain used.
    private nonisolated func query(_ key: String?, accessible: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let key { query[kSecAttrAccount as String] = key }
        if accessible { query[kSecAttrAccessible as String] = accessibility.secAccessibility }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private static func describe(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus"
        return "\(message) (\(status))"
    }
}
