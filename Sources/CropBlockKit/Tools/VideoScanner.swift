import Foundation

public struct VideoScanResult: Hashable, Sendable {
    public let inspection: VideoInspection
    public let detection: CropDetectionResult

    public init(inspection: VideoInspection, detection: CropDetectionResult) {
        self.inspection = inspection
        self.detection = detection
    }
}

public enum VideoScannerError: Error, LocalizedError, Sendable {
    case missingTool(String)

    public var errorDescription: String? {
        switch self {
        case .missingTool(let tool):
            "Required tool '\(tool)' is missing. Open Tool Setup to install or locate it."
        }
    }
}

/// Orchestrates `MatroskaHeaderReader` + `ffprobe` + Standard or Deep `ffmpeg cropdetect` +
/// representative preview frame extraction for a single MKV file, supporting cooperative cancellation.
public enum VideoScanner {

    public static func scan(
        url: URL,
        settings: DetectionSettings,
        tools: ResolvedTools,
        previewCacheDirectory: URL,
        mode: ScanMode = .standard,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> VideoScanResult {
        try Task.checkCancellation()

        guard let ffprobe = tools.ffprobeURL else {
            throw VideoScannerError.missingTool("ffprobe")
        }
        guard let ffmpeg = tools.ffmpegURL else {
            throw VideoScannerError.missingTool("ffmpeg")
        }

        // 1. Read raw Matroska EBML header (instant O(1) seek, including SeekHead EOF Tracks).
        let mkvHeader = try MatroskaHeaderReader.readVideoHeader(at: url)
        try Task.checkCancellation()

        // 2. Probe encoded resolution, SAR, codec, and duration via ffprobe.
        let probe = try await FFprobeParser.probe(url: url, ffprobe: ffprobe)
        try Task.checkCancellation()

        let storedWidth = mkvHeader.pixelWidth ?? probe.width
        let storedHeight = mkvHeader.pixelHeight ?? probe.height
        let effectiveSAR = CropCalculator.effectiveSAR(
            ffprobeSAR: probe.sar,
            originalHeader: mkvHeader,
            storedWidth: storedWidth,
            storedHeight: storedHeight
        )
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0

        let inspection = VideoInspection(
            url: url,
            fileSize: fileSize,
            storedWidth: storedWidth,
            storedHeight: storedHeight,
            sar: effectiveSAR,
            duration: probe.duration,
            codecName: probe.codecName,
            currentHeader: mkvHeader
        )

        // 3. Schedule Standard or Deep Scan windows and run cropdetect across them.
        let windows: [SampleWindow]
        let isFullVideoSinglePass: Bool
        switch mode {
        case .standard:
            windows = CropCalculator.sampleWindows(duration: probe.duration, settings: settings)
            isFullVideoSinglePass = false
        case .deep:
            let deepPlan = CropCalculator.deepScanWindows(duration: probe.duration, settings: settings)
            windows = deepPlan.windows
            isFullVideoSinglePass = deepPlan.isFullVideoSinglePass
        }

        var samples: [CropSample] = []
        samples.reserveCapacity(windows.count)

        for (idx, window) in windows.enumerated() {
            try Task.checkCancellation()
            onProgress?(idx + 1, windows.count)
            let sample = try await CropDetectRunner.detectSample(
                url: url,
                window: window,
                settings: settings,
                ffmpeg: ffmpeg
            )
            samples.append(sample)
        }

        // 4. Select representative preview indices (all 3 for standard; up to 5 for Deep Scan,
        //    prioritizing outlier/Variable AR frames) and extract only those preview JPEGs.
        let fileKey = String(abs(MKVFileDiscovery.canonicalPath(for: url).hashValue))
        let modeTag = mode.rawValue
        let previewIndices: [Int] = mode == .deep
            ? CropCalculator.selectPreviewIndices(samples: samples, maxCount: 5)
            : Array(0..<samples.count)

        for idx in previewIndices {
            try Task.checkCancellation()
            let previewURL = previewCacheDirectory
                .appending(path: "\(fileKey)-\(modeTag)-sample-\(idx).jpg")
            if let extracted = try? await FrameExtractor.extractFrame(
                from: url,
                window: samples[idx].window,
                outputURL: previewURL,
                ffmpeg: ffmpeg
            ) {
                samples[idx].previewImagePath = extracted.path
            }
        }

        let detection = CropCalculator.unionAndAnalyze(
            samples: samples,
            frameWidth: storedWidth,
            frameHeight: storedHeight,
            noiseFloor: settings.noiseFloorPixels,
            scanMode: mode,
            isFullVideoSinglePass: isFullVideoSinglePass
        )

        return VideoScanResult(inspection: inspection, detection: detection)
    }
}
