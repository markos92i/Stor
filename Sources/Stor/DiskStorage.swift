//
//  DiskStorage.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 18/07/2026.
//

import Foundation
import Logy

// MARK: - DiskStorage

/// File-system backed `StorageBackend`. One file per key, atomic writes.
public actor DiskStorage: StorageBackend {

    public nonisolated let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private nonisolated let log = Logy<StorLog>()

    public init(directory: URL, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.directory = directory
        self.encoder = encoder
        self.decoder = decoder
        Self.createDirectoryIfNeeded(at: directory)
    }

    public nonisolated var location: String { "disk:\(directory.path())" }

    // MARK: - StorageBackend

    public func write(_ data: Data, for key: String) {
        do {
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            log.log(.failed(key: key, store: .disk, step: "write", detail: error.localizedDescription))
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
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log.log(.failed(key: key, store: .disk, step: "remove", detail: error.localizedDescription))
        }
    }

    public func removeAll() {
        allKeys().forEach { remove($0) }
    }

    public func purge() {
        try? FileManager.default.removeItem(at: directory)
        Self.createDirectoryIfNeeded(at: directory)
    }

    /// A file that exists but can't be read (e.g. protected while the device is locked) is `unavailable`.
    public nonisolated func readSync(_ key: String) -> ReadResult {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path()) else { return .missing }
        do {
            return .found(try Data(contentsOf: url))
        } catch {
            log.log(.unavailable(key: key, store: .disk, detail: error.localizedDescription))
            return .unavailable
        }
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
