import Foundation

public enum CropDetectError: Error, LocalizedError, Sendable {
    case ffmpegFailed(String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegFailed(let detail): "ffmpeg cropdetect failed: \(detail)"
        }
    }
}

/// Runs multi-timestamp `ffmpeg cropdetect` using `-apply_cropping codec` (so codec SPS macroblock
/// cropping like 1088→1080 is preserved while Matroska container `PixelCrop*` is ignored).
public enum CropDetectRunner {

    /// Parses the accumulated active crop rect from `ffmpeg cropdetect` stderr output.
    /// With `reset=0`, the final non-zero `crop=w:h:x:y` line represents the sample's accumulated union.
    /// Returns `(rect: nil, isAllBlack: true)` when cropdetect emitted frames that were entirely black.
    public static func parseCropDetectOutput(_ stderr: String) -> (rect: CropRect?, isAllBlack: Bool) {
        var lastValidRect: CropRect?
        var sawCropLine = false

        for line in stderr.split(whereSeparator: \.isNewline) {
            guard let cropRange = line.range(of: "crop=") else { continue }
            sawCropLine = true
            let tail = line[cropRange.upperBound...]
            let token = tail.prefix { !$0.isWhitespace }
            let parts = token.split(separator: ":")
            guard parts.count == 4,
                  let w = Int(parts[0]),
                  let h = Int(parts[1]),
                  let x = Int(parts[2]),
                  let y = Int(parts[3]) else {
                continue
            }
            if w > 0 && h > 0 && x >= 0 && y >= 0 {
                lastValidRect = CropRect(x: x, y: y, width: w, height: h)
            }
        }

        if let lastValidRect {
            return (lastValidRect, false)
        }
        return (nil, sawCropLine)
    }

    /// Scans one timestamp window and returns its detected `CropSample`.
    public static func detectSample(
        url: URL,
        window: SampleWindow,
        settings: DetectionSettings,
        ffmpeg: URL
    ) async throws -> CropSample {
        let output = try await runCropDetect(
            url: url,
            window: window,
            settings: settings,
            ffmpeg: ffmpeg,
            useApplyCroppingCodec: true
        )
        let parsed = parseCropDetectOutput(output.stderrString)
        return CropSample(
            window: window,
            detectedRect: parsed.rect,
            isAllBlack: parsed.isAllBlack
        )
    }

    private static func runCropDetect(
        url: URL,
        window: SampleWindow,
        settings: DetectionSettings,
        ffmpeg: URL,
        useApplyCroppingCodec: Bool
    ) async throws -> ProcessOutput {
        var args: [String] = [
            "-hide_banner",
            "-nostdin",
            "-loglevel", "info",
        ]
        if useApplyCroppingCodec {
            args += ["-apply_cropping", "codec"]
        }
        args += [
            "-ss", String(format: "%.2f", window.startTime),
            "-t", String(format: "%.2f", window.duration),
            "-i", url.path,
            "-map", "0:v:0",
            "-vf", "cropdetect=limit=\(settings.cropDetectLimit):round=2:reset=0",
            "-an", "-sn", "-dn",
            "-f", "null",
            "-",
        ]

        let output = try await ProcessRunner.run(executable: ffmpeg, arguments: args)
        if output.terminationStatus != 0 {
            let err = output.stderrString
            // Fallback gracefully for older FFmpeg (< 7.0) that does not support `-apply_cropping codec`.
            if useApplyCroppingCodec && (err.contains("Unrecognized option 'apply_cropping'") || err.contains("Error parsing option 'apply_cropping'") || err.contains("Invalid argument")) {
                return try await runCropDetect(
                    url: url,
                    window: window,
                    settings: settings,
                    ffmpeg: ffmpeg,
                    useApplyCroppingCodec: false
                )
            }
            let summary = err.split(whereSeparator: \.isNewline).last.map(String.init) ?? "exit code \(output.terminationStatus)"
            throw CropDetectError.ffmpegFailed(summary)
        }
        return output
    }
}
