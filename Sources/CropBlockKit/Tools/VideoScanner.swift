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

/// Orchestrates `MatroskaHeaderReader` + `ffprobe` + multi-timestamp `ffmpeg cropdetect` +
/// preview frame extraction for a single MKV file, supporting cooperative Swift Task cancellation.
public enum VideoScanner {

    public static func scan(
        url: URL,
        settings: DetectionSettings,
        tools: ResolvedTools,
        previewCacheDirectory: URL
    ) async throws -> VideoScanResult {
        try Task.checkCancellation()

        guard let ffprobe = tools.ffprobeURL else {
            throw VideoScannerError.missingTool("ffprobe")
        }
        guard let ffmpeg = tools.ffmpegURL else {
            throw VideoScannerError.missingTool("ffmpeg")
        }

        // 1. Read raw Matroska EBML header (instant O(1) seek, even if Tracks sits at EOF via SeekHead).
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

        // 3. Run multi-timestamp cropdetect + extract preview frame for each window.
        let windows = CropCalculator.sampleWindows(duration: probe.duration, settings: settings)
        let fileKey = String(abs(MKVFileDiscovery.canonicalPath(for: url).hashValue))
        var samples: [CropSample] = []
        samples.reserveCapacity(windows.count)

        for window in windows {
            try Task.checkCancellation()
            var sample = try await CropDetectRunner.detectSample(
                url: url,
                window: window,
                settings: settings,
                ffmpeg: ffmpeg
            )
            try Task.checkCancellation()

            let previewURL = previewCacheDirectory
                .appending(path: "\(fileKey)-sample-\(window.index).jpg")
            if let extracted = try? await FrameExtractor.extractFrame(
                from: url,
                window: window,
                outputURL: previewURL,
                ffmpeg: ffmpeg
            ) {
                sample.previewImagePath = extracted.path
            }
            samples.append(sample)
        }

        let detection = CropCalculator.unionAndAnalyze(
            samples: samples,
            frameWidth: storedWidth,
            frameHeight: storedHeight,
            noiseFloor: settings.noiseFloorPixels
        )

        return VideoScanResult(inspection: inspection, detection: detection)
    }
}
