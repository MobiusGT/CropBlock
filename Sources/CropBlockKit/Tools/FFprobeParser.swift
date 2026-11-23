import Foundation

public enum FFprobeError: Error, LocalizedError, Sendable {
    case commandFailed(String)
    case invalidJSON
    case missingVideoStream
    case invalidDimensions

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): "ffprobe failed: \(detail)"
        case .invalidJSON: "Unable to parse ffprobe metadata output."
        case .missingVideoStream: "File contains no video stream."
        case .invalidDimensions: "Video stream reported invalid frame dimensions."
        }
    }
}

public struct FFprobeVideoMetadata: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let sar: SampleAspectRatio?
    public let duration: Double
    public let codecName: String

    public init(width: Int, height: Int, sar: SampleAspectRatio?, duration: Double, codecName: String) {
        self.width = width
        self.height = height
        self.sar = sar
        self.duration = duration
        self.codecName = codecName
    }
}

public enum FFprobeParser {
    private struct ProbeResponse: Decodable {
        struct Stream: Decodable {
            let width: Int?
            let height: Int?
            let sampleAspectRatio: String?
            let codecName: String?
            let duration: String?
            let tags: [String: String]?

            enum CodingKeys: String, CodingKey {
                case width, height, duration, tags
                case sampleAspectRatio = "sample_aspect_ratio"
                case codecName = "codec_name"
            }
        }

        struct Format: Decodable {
            let duration: String?
        }

        let streams: [Stream]?
        let format: Format?
    }

    public static func probe(url: URL, ffprobe: URL) async throws -> FFprobeVideoMetadata {
        let args = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,sample_aspect_ratio,codec_name,duration:stream_tags=DURATION",
            "-show_entries", "format=duration",
            "-of", "json",
            url.path,
        ]
        let output = try await ProcessRunner.run(executable: ffprobe, arguments: args)
        guard output.terminationStatus == 0 else {
            let msg = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw FFprobeError.commandFailed(msg.isEmpty ? "exit code \(output.terminationStatus)" : msg)
        }
        return try parse(jsonData: output.stdout)
    }

    public static func parse(jsonData: Data) throws -> FFprobeVideoMetadata {
        let decoded: ProbeResponse
        do {
            decoded = try JSONDecoder().decode(ProbeResponse.self, from: jsonData)
        } catch {
            throw FFprobeError.invalidJSON
        }
        guard let stream = decoded.streams?.first else {
            throw FFprobeError.missingVideoStream
        }
        guard let width = stream.width, let height = stream.height, width > 0, height > 0 else {
            throw FFprobeError.invalidDimensions
        }

        let sar = SampleAspectRatio.parse(stream.sampleAspectRatio)
        let duration = parseDuration(
            formatDuration: decoded.format?.duration,
            streamDuration: stream.duration,
            tagDuration: stream.tags?["DURATION"] ?? stream.tags?["duration"]
        )
        let codecName = stream.codecName ?? "unknown"
        return FFprobeVideoMetadata(width: width, height: height, sar: sar, duration: duration, codecName: codecName)
    }

    private static func parseDuration(formatDuration: String?, streamDuration: String?, tagDuration: String?) -> Double {
        if let s = formatDuration, let v = Double(s), v.isFinite, v > 0 { return v }
        if let s = streamDuration, let v = Double(s), v.isFinite, v > 0 { return v }
        if let tag = tagDuration {
            // Format "HH:MM:SS.nnnnnnnnn"
            let parts = tag.split(separator: ":")
            if parts.count == 3,
               let h = Double(parts[0]),
               let m = Double(parts[1]),
               let s = Double(parts[2]) {
                let total = h * 3600 + m * 60 + s
                if total.isFinite, total > 0 { return total }
            }
        }
        return 0
    }
}
