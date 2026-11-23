import Foundation

/// Extracts uncropped (codec-cropped only) preview frames for visual crop overlay verification.
public enum FrameExtractor {

    /// Extracts one JPEG preview frame near the midpoint of `window` into `outputURL`.
    public static func extractFrame(
        from videoURL: URL,
        window: SampleWindow,
        outputURL: URL,
        ffmpeg: URL
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let seekTarget = window.startTime + min(2.0, window.duration / 2.0)

        let success = try await attemptExtract(
            videoURL: videoURL,
            seekTime: seekTarget,
            outputURL: outputURL,
            ffmpeg: ffmpeg,
            useApplyCroppingCodec: true
        )
        if !success {
            // Fallback to start of window if midpoint seek hit EOF on a short clip.
            _ = try await attemptExtract(
                videoURL: videoURL,
                seekTime: max(0, window.startTime),
                outputURL: outputURL,
                ffmpeg: ffmpeg,
                useApplyCroppingCodec: true
            )
        }
        return outputURL
    }

    private static func attemptExtract(
        videoURL: URL,
        seekTime: Double,
        outputURL: URL,
        ffmpeg: URL,
        useApplyCroppingCodec: Bool
    ) async throws -> Bool {
        var args: [String] = [
            "-hide_banner",
            "-nostdin",
            "-loglevel", "error",
            "-y",
        ]
        if useApplyCroppingCodec {
            args += ["-apply_cropping", "codec"]
        }
        args += [
            "-ss", String(format: "%.2f", seekTime),
            "-i", videoURL.path,
            "-map", "0:v:0",
            "-frames:v", "1",
            "-q:v", "3",
            outputURL.path,
        ]
        let out = try await ProcessRunner.run(executable: ffmpeg, arguments: args)
        if out.terminationStatus != 0 && useApplyCroppingCodec {
            let err = out.stderrString
            if err.contains("apply_cropping") {
                return try await attemptExtract(
                    videoURL: videoURL,
                    seekTime: seekTime,
                    outputURL: outputURL,
                    ffmpeg: ffmpeg,
                    useApplyCroppingCodec: false
                )
            }
        }
        return out.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path)
    }
}
