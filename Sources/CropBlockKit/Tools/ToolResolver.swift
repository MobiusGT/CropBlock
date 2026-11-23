import Foundation

public enum ExternalTool: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case ffmpeg
    case ffprobe
    case mkvpropedit

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var purpose: String {
        switch self {
        case .ffmpeg: "Detects black bars (cropdetect) and extracts sample preview frames."
        case .ffprobe: "Reads encoded resolution, SAR, codec, and duration."
        case .mkvpropedit: "Edits Matroska track headers losslessly in-place."
        }
    }
}

public enum ToolSource: String, Codable, Hashable, Sendable {
    case custom = "Custom"
    case bundled = "Bundled"
    case homebrew = "Homebrew"
    case path = "PATH"
}

public enum ToolStatus: Hashable, Sendable {
    case found(url: URL, source: ToolSource, version: String?)
    case missing(reason: String)

    public var isAvailable: Bool {
        if case .found = self { return true }
        return false
    }

    public var url: URL? {
        if case .found(let url, _, _) = self { return url }
        return nil
    }

    public var source: ToolSource? {
        if case .found(_, let source, _) = self { return source }
        return nil
    }

    public var version: String? {
        if case .found(_, _, let version) = self { return version }
        return nil
    }
}

public struct CustomToolPaths: Codable, Hashable, Sendable {
    public var ffmpeg: String
    public var ffprobe: String
    public var mkvpropedit: String

    public static let empty = CustomToolPaths(ffmpeg: "", ffprobe: "", mkvpropedit: "")

    public init(ffmpeg: String = "", ffprobe: String = "", mkvpropedit: String = "") {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.mkvpropedit = mkvpropedit
    }

    public subscript(tool: ExternalTool) -> String {
        get {
            switch tool {
            case .ffmpeg: ffmpeg
            case .ffprobe: ffprobe
            case .mkvpropedit: mkvpropedit
            }
        }
        set {
            switch tool {
            case .ffmpeg: ffmpeg = newValue
            case .ffprobe: ffprobe = newValue
            case .mkvpropedit: mkvpropedit = newValue
            }
        }
    }
}

public struct ResolvedTools: Hashable, Sendable {
    public var statuses: [ExternalTool: ToolStatus]

    public init(statuses: [ExternalTool: ToolStatus]) {
        self.statuses = statuses
    }

    public subscript(tool: ExternalTool) -> ToolStatus {
        statuses[tool] ?? .missing(reason: "Not checked.")
    }

    public var allAvailable: Bool {
        ExternalTool.allCases.allSatisfy { self[$0].isAvailable }
    }

    public var missingTools: [ExternalTool] {
        ExternalTool.allCases.filter { !self[$0].isAvailable }
    }

    public var ffmpegURL: URL? { self[.ffmpeg].url }
    public var ffprobeURL: URL? { self[.ffprobe].url }
    public var mkvpropeditURL: URL? { self[.mkvpropedit].url }
}

/// Discovers `ffmpeg`, `ffprobe`, and `mkvpropedit` in strict priority order:
/// 1. Explicit custom path in Settings (whenever non-empty)
/// 2. Bundled helper inside `<App>.app/Contents/Helpers/`
/// 3. Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`) and `$PATH`
public struct ToolResolver: Sendable {
    public let bundledHelpersDirectory: URL?
    public let homebrewDirectories: [URL]
    public let searchPath: String

    public init(
        bundledHelpersDirectory: URL? = Bundle.main.bundleURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory),
        homebrewDirectories: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ],
        searchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.bundledHelpersDirectory = bundledHelpersDirectory
        self.homebrewDirectories = homebrewDirectories
        self.searchPath = searchPath
    }

    /// Synchronous resolution of paths (without spawning version probes).
    public func resolveAll(customPaths: CustomToolPaths = .empty) -> ResolvedTools {
        var result: [ExternalTool: ToolStatus] = [:]
        for tool in ExternalTool.allCases {
            result[tool] = resolve(tool, customPath: customPaths[tool])
        }
        return ResolvedTools(statuses: result)
    }

    /// Resolves paths and fetches short version strings in parallel for display in Tool Setup & Settings.
    public func resolveAllWithVersions(customPaths: CustomToolPaths = .empty) async -> ResolvedTools {
        let base = resolveAll(customPaths: customPaths)
        var enriched = base.statuses

        await withTaskGroup(of: (ExternalTool, ToolStatus).self) { group in
            for tool in ExternalTool.allCases {
                let status = base[tool]
                group.addTask {
                    guard case .found(let url, let source, _) = status else {
                        return (tool, status)
                    }
                    let version = await Self.probeVersion(for: tool, at: url)
                    return (tool, .found(url: url, source: source, version: version))
                }
            }
            for await (tool, status) in group {
                enriched[tool] = status
            }
        }
        return ResolvedTools(statuses: enriched)
    }

    public func resolve(_ tool: ExternalTool, customPath: String = "") -> ToolStatus {
        let trimmedCustom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Explicit custom path always wins when configured.
        if !trimmedCustom.isEmpty {
            let expanded = NSString(string: trimmedCustom).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if Self.isExecutableRegularFile(at: url) {
                return .found(url: url, source: .custom, version: nil)
            }
            return .missing(reason: "Custom path is not an executable file: \(trimmedCustom)")
        }

        // 2. Bundled helper inside Contents/Helpers/
        if let helpersDir = bundledHelpersDirectory {
            let candidate = helpersDir.appending(path: tool.rawValue)
            if Self.isExecutableRegularFile(at: candidate) {
                return .found(url: candidate, source: .bundled, version: nil)
            }
        }

        // 3. Common Homebrew locations
        for dir in homebrewDirectories {
            let candidate = dir.appending(path: tool.rawValue)
            if Self.isExecutableRegularFile(at: candidate) {
                return .found(url: candidate, source: .homebrew, version: nil)
            }
        }

        // 4. $PATH directories (deduplicated against Homebrew dirs)
        let seenDirs = Set(homebrewDirectories.map { $0.standardizedFileURL.path })
        for rawDir in searchPath.split(separator: ":").map(String.init) where !rawDir.isEmpty {
            let dirURL = URL(fileURLWithPath: rawDir, isDirectory: true).standardizedFileURL
            if seenDirs.contains(dirURL.path) { continue }
            let candidate = dirURL.appending(path: tool.rawValue)
            if Self.isExecutableRegularFile(at: candidate) {
                return .found(url: candidate, source: .path, version: nil)
            }
        }

        return .missing(reason: "\(tool.rawValue) not found in bundled helpers, Homebrew, or PATH.")
    }

    public static func isExecutableRegularFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        return fm.isExecutableFile(atPath: url.path)
    }

    private static func probeVersion(for tool: ExternalTool, at url: URL) async -> String? {
        let args = tool == .mkvpropedit ? ["--version"] : ["-version"]
        guard let output = try? await ProcessRunner.run(executable: url, arguments: args),
              output.terminationStatus == 0 else {
            return nil
        }
        let firstLine = output.stdoutString
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = firstLine, !line.isEmpty else { return nil }
        return parseShortVersion(from: line, tool: tool)
    }

    public static func parseShortVersion(from firstLine: String, tool: ExternalTool) -> String {
        switch tool {
        case .ffmpeg, .ffprobe:
            // "ffmpeg version 9.0.1 Copyright ..." -> "9.0.1"
            let parts = firstLine.split(separator: " ")
            if let idx = parts.firstIndex(of: "version"), idx + 1 < parts.count {
                return String(parts[idx + 1])
            }
            return firstLine
        case .mkvpropedit:
            // "mkvpropedit v99.0 ('Buka') 64-bit" -> "v99.0"
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2 {
                return String(parts[1])
            }
            return firstLine
        }
    }
}
