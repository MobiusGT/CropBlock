import Foundation

/// Atomic JSON store persisting original Matroska headers per file so 1-Click Restore
/// works reliably even after quitting and relaunching Crop Block.
public actor ReceiptStore {
    private let fileURL: URL
    private var cache: [String: EditReceipt]

    public init(directoryURL: URL) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.fileURL = directoryURL.appending(path: "receipts.json")
        self.cache = Self.loadFromDisk(at: fileURL)
    }

    public func receipt(for url: URL) -> EditReceipt? {
        cache[MKVFileDiscovery.canonicalPath(for: url)]
    }

    public func receipt(forCanonicalPath path: String) -> EditReceipt? {
        cache[path]
    }

    public func allReceipts() -> [EditReceipt] {
        Array(cache.values).sorted { $0.appliedAt > $1.appliedAt }
    }

    public func save(_ receipt: EditReceipt) throws {
        cache[receipt.canonicalPath] = receipt
        try persistToDisk()
    }

    public func remove(for url: URL) throws {
        let key = MKVFileDiscovery.canonicalPath(for: url)
        cache.removeValue(forKey: key)
        try persistToDisk()
    }

    public func removeAll() throws {
        cache.removeAll()
        try persistToDisk()
    }

    private func persistToDisk() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadFromDisk(at url: URL) -> [String: EditReceipt] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: EditReceipt].self, from: data)) ?? [:]
    }
}
