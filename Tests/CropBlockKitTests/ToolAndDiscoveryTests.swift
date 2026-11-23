import Foundation
import Testing
@testable import CropBlockKit

@Suite("ToolResolver, parsers, and MKVFileDiscovery")
struct ToolAndDiscoveryTests {

    private func makeExecutable(in dir: URL, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("ToolResolver precedence: Custom > Bundled > Homebrew > PATH")
    func toolResolverPrecedence() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cb-resolver-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let customDir = root.appending(path: "custom")
        let bundledDir = root.appending(path: "bundled")
        let brewDir = root.appending(path: "brew")
        let pathDir = root.appending(path: "path")

        let customFF = try makeExecutable(in: customDir, name: "ffmpeg")
        let bundledFF = try makeExecutable(in: bundledDir, name: "ffmpeg")
        _ = try makeExecutable(in: brewDir, name: "ffmpeg")
        let brewProbe = try makeExecutable(in: brewDir, name: "ffprobe")
        let pathMkv = try makeExecutable(in: pathDir, name: "mkvpropedit")

        let resolver = ToolResolver(
            bundledHelpersDirectory: bundledDir,
            homebrewDirectories: [brewDir],
            searchPath: pathDir.path
        )

        // 1. Custom path takes priority #1 over bundled/homebrew/PATH
        let withCustom = resolver.resolveAll(customPaths: CustomToolPaths(ffmpeg: customFF.path))
        #expect(withCustom[.ffmpeg].url == customFF)
        #expect(withCustom[.ffmpeg].source == .custom)
        #expect(withCustom[.ffprobe].url == brewProbe)
        #expect(withCustom[.ffprobe].source == .homebrew)
        #expect(withCustom[.mkvpropedit].url == pathMkv)
        #expect(withCustom[.mkvpropedit].source == .path)
        #expect(withCustom.allAvailable)

        // 2. Without custom path, bundled wins over Homebrew
        let withoutCustom = resolver.resolveAll(customPaths: .empty)
        #expect(withoutCustom[.ffmpeg].url == bundledFF)
        #expect(withoutCustom[.ffmpeg].source == .bundled)

        // 3. Invalid custom path reports missing instead of silently falling back
        let brokenCustom = resolver.resolve(.ffmpeg, customPath: root.appending(path: "does-not-exist").path)
        #expect(!brokenCustom.isAvailable)
    }

    @Test("Short version parsing handles ffmpeg, ffprobe, and mkvpropedit headers")
    func versionParsing() {
        #expect(ToolResolver.parseShortVersion(from: "ffmpeg version 9.0.1 Copyright (c) 2000-2026", tool: .ffmpeg) == "9.0.1")
        #expect(ToolResolver.parseShortVersion(from: "ffprobe version 7.1.1 Copyright", tool: .ffprobe) == "7.1.1")
        #expect(ToolResolver.parseShortVersion(from: "mkvpropedit v99.0 ('Buka') 64-bit", tool: .mkvpropedit) == "v99.0")
    }

    @Test("CropDetect stderr parser extracts accumulated union and detects all-black samples")
    func cropDetectStderrParsing() {
        let log = """
        [Parsed_cropdetect_0 @ 0x1] x1:0 x2:1919 y1:200 y2:879 w:1920 h:680 x:0 y:200 pts:100 t:0.1 limit:24 crop=1920:680:0:200
        [Parsed_cropdetect_0 @ 0x1] x1:0 x2:1919 y1:140 y2:939 w:1920 h:800 x:0 y:140 pts:2400 t:2.4 limit:24 crop=1920:800:0:140
        """
        let parsed = CropDetectRunner.parseCropDetectOutput(log)
        #expect(!parsed.isAllBlack)
        #expect(parsed.rect == CropRect(x: 0, y: 140, width: 1920, height: 800))

        let blackLog = """
        [Parsed_cropdetect_0 @ 0x1] x1:1919 x2:0 y1:1079 y2:0 w:0 h:0 x:0 y:0 pts:100 t:0.1 limit:24 crop=0:0:0:0
        """
        let black = CropDetectRunner.parseCropDetectOutput(blackLog)
        #expect(black.isAllBlack)
        #expect(black.rect == nil)
    }

    @Test("FFprobeParser decodes dimensions, SAR, codec, and fallback tag duration")
    func ffprobeJSONParsing() throws {
        let json = """
        {
          "streams": [{
            "width": 720,
            "height": 480,
            "sample_aspect_ratio": "32:27",
            "codec_name": "h264",
            "tags": { "DURATION": "01:30:05.500000000" }
          }],
          "format": {}
        }
        """
        let meta = try FFprobeParser.parse(jsonData: Data(json.utf8))
        #expect(meta.width == 720)
        #expect(meta.height == 480)
        #expect(meta.sar == SampleAspectRatio(numerator: 32, denominator: 27))
        #expect(meta.codecName == "h264")
        #expect(abs(meta.duration - 5405.5) < 0.01)
    }

    @Test("MKVFileDiscovery scans folders recursively, skips hidden/non-MKV, deduplicates, and disambiguates duplicates")
    func fileDiscoveryAndDisambiguation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cb-discover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let s1 = root.appending(path: "Season 1")
        let s2 = root.appending(path: "Season 2")
        let hiddenDir = root.appending(path: ".TrashCache")
        try FileManager.default.createDirectory(at: s1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: s2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)

        let ep1S1 = s1.appending(path: "Episode 01.mkv")
        let ep1S2 = s2.appending(path: "Episode 01.MKV")
        let unique = s1.appending(path: "Special.mkv")
        let hiddenFile = s1.appending(path: ".Hidden.mkv")
        let insideHidden = hiddenDir.appending(path: "Inside.mkv")
        let mp4File = s1.appending(path: "Trailer.mp4")

        for u in [ep1S1, ep1S2, unique, hiddenFile, insideHidden, mp4File] {
            try Data().write(to: u)
        }

        // Drop folder + duplicate explicit file + explicit mp4
        let result = MKVFileDiscovery.discoverMKVFiles(from: [root, ep1S1, mp4File])
        #expect(result.urls.count == 3)
        #expect(result.skippedNonMKVCount == 1)
        let names = Set(result.urls.map(\.lastPathComponent))
        #expect(names.contains("Episode 01.mkv"))
        #expect(names.contains("Episode 01.MKV"))
        #expect(names.contains("Special.mkv"))
        #expect(!names.contains(".Hidden.mkv"))
        #expect(!names.contains("Inside.mkv"))

        // Parent folder disambiguation applies only to colliding filenames
        let labels = MKVFileDiscovery.parentContextLabels(for: result.urls)
        #expect(labels[MKVFileDiscovery.canonicalPath(for: ep1S1)] == "Season 1")
        #expect(labels[MKVFileDiscovery.canonicalPath(for: ep1S2)] == "Season 2")
        #expect(labels[MKVFileDiscovery.canonicalPath(for: unique)] == nil)
    }
}
