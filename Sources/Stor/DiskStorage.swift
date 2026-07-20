//
//  DiskStorage.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 18/07/2026.
//

import Foundation

// MARK: - DiskStorage

/// File-system backed `StorageBackend`. One file per key, atomic writes.
public actor DiskStorage: StorageBackend {

    public nonisolated let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.directory = directory
        self.encoder = encoder
        self.decoder = decoder
        Self.createDirectoryIfNeeded(at: directory)
    }

    // MARK: - StorageBackend

    public func write(_ data: Data, for key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    public func read(_ key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    public func readAll() -> [String: Data] {
        allKeys().reduce(into: [:]) { result, key in
            if let data = read(key) { result[key] = data }
        }
    }

    public func allKeys() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return contents.filter { !$0.hasDirectoryPath }.map { $0.lastPathComponent }
    }

    public func remove(_ key: String) {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func removeAll() {
        allKeys().forEach { remove($0) }
    }

    public func purge() {
        try? FileManager.default.removeItem(at: directory)
        Self.createDirectoryIfNeeded(at: directory)
    }

    public nonisolated func readSync(_ key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    // MARK: - Helpers

    public nonisolated func fileURL(for key: String) -> URL {
        directory.appending(component: key)
    }

    private static func createDirectoryIfNeeded(at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path()) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
