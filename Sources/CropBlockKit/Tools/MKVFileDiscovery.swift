import Foundation

/// Recursively discovers `.mkv` files from dropped/selected files and folders,
/// skipping hidden items and non-MKV files, deduplicating canonical paths, and
/// computing parent-folder context labels whenever two queued files share the same filename.
public enum MKVFileDiscovery {

    public struct DiscoveryResult: Hashable, Sendable {
        public let urls: [URL]
        public let skippedNonMKVCount: Int

        public init(urls: [URL], skippedNonMKVCount: Int) {
            self.urls = urls
            self.skippedNonMKVCount = skippedNonMKVCount
        }
    }

    public static func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func discoverMKVFiles(
        from inputs: [URL],
        existingCanonicalPaths: Set<String> = []
    ) -> DiscoveryResult {
        let fm = FileManager.default
        var seen = existingCanonicalPaths
        var found: [URL] = []
        var skipped = 0

        for rawURL in inputs {
            let url = rawURL.standardizedFileURL
            guard !isHiddenItem(url) else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                    options: options
                ) else { continue }

                var folderMatches: [URL] = []
                for case let childURL as URL in enumerator {
                    guard !isHiddenItem(childURL) else { continue }
                    let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey])
                    if values?.isDirectory == true { continue }
                    guard isMKVFile(childURL) else { continue }
                    folderMatches.append(childURL.standardizedFileURL)
                }
                folderMatches.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                for match in folderMatches {
                    let canonical = canonicalPath(for: match)
                    if seen.insert(canonical).inserted {
                        found.append(match)
                    }
                }
            } else {
                if isMKVFile(url) {
                    let canonical = canonicalPath(for: url)
                    if seen.insert(canonical).inserted {
                        found.append(url)
                    }
                } else {
                    skipped += 1
                }
            }
        }

        return DiscoveryResult(urls: found, skippedNonMKVCount: skipped)
    }

    /// Returns a map of canonicalPath -> disambiguating parent folder label for URLs whose filenames collide.
    /// Unique filenames map to `nil` so the queue stays clean and uncluttered.
    public static func parentContextLabels(for urls: [URL]) -> [String: String] {
        let grouped = Dictionary(grouping: urls) { $0.lastPathComponent.lowercased() }
        var labels: [String: String] = [:]

        for (_, group) in grouped where group.count > 1 {
            // Try 1 parent folder first; if those also collide, include 2 parent components.
            let oneParent = group.map { url -> (String, String) in
                let parent = url.deletingLastPathComponent().lastPathComponent
                return (canonicalPath(for: url), parent)
            }
            let uniqueOne = Set(oneParent.map(\.1))
            if uniqueOne.count == group.count {
                for (path, label) in oneParent where !label.isEmpty {
                    labels[path] = label
                }
            } else {
                for url in group {
                    let comps = url.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
                    let suffix = comps.suffix(2).joined(separator: "/")
                    if !suffix.isEmpty {
                        labels[canonicalPath(for: url)] = suffix
                    }
                }
            }
        }
        return labels
    }

    private static func isMKVFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("mkv") == .orderedSame
    }

    private static func isHiddenItem(_ url: URL) -> Bool {
        if url.lastPathComponent.hasPrefix(".") { return true }
        if let values = try? url.resourceValues(forKeys: [.isHiddenKey]), values.isHidden == true {
            return true
        }
        return false
    }
}
