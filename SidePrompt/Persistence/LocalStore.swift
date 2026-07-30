import Foundation

struct LocalStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.encoder = Self.makeEncoder()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> AppStoreData {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = AppStoreData.empty
            try save(empty)
            return empty
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppStoreData.self, from: data)
    }

    func save(_ store: AppStoreData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: [.atomic])
    }

    var path: String { fileURL.path }

    /// Background writer for the debounced save path — keeps encoding off the main thread.
    func makeWriter() -> StoreWriter {
        StoreWriter(fileURL: fileURL)
    }

    fileprivate static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // No .prettyPrinted: this file is rewritten on every mutation.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("SidePrompt", isDirectory: true)
            .appendingPathComponent("store.json")
    }
}

/// Owns its own encoder so `QueueStore` can hand off writes without blocking the main actor.
actor StoreWriter {
    private let fileURL: URL
    private let encoder: JSONEncoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = LocalStore.makeEncoder()
    }

    func write(_ store: AppStoreData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: [.atomic])
    }
}
