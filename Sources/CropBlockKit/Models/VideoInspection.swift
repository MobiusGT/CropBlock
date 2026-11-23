import Foundation

/// Combined video metadata from `ffprobe` and direct Matroska EBML header inspection.
public struct VideoInspection: Codable, Hashable, Sendable {
    public let url: URL
    public let fileSize: Int64
    public let storedWidth: Int
    public let storedHeight: Int
    public let sar: SampleAspectRatio
    public let duration: Double
    public let codecName: String
    /// Raw Matroska track v1 video header currently stored on disk.
    public var currentHeader: MatroskaVideoHeader

    public init(
        url: URL,
        fileSize: Int64,
        storedWidth: Int,
        storedHeight: Int,
        sar: SampleAspectRatio,
        duration: Double,
        codecName: String,
        currentHeader: MatroskaVideoHeader
    ) {
        self.url = url
        self.fileSize = fileSize
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.sar = sar
        self.duration = duration
        self.codecName = codecName
        self.currentHeader = currentHeader
    }

    /// Uncropped full-frame display dimensions accounting for SAR.
    public var fullFrameDisplayDimensions: DisplayDimensions {
        CropCalculator.displayDimensions(
            storedWidth: storedWidth,
            storedHeight: storedHeight,
            insets: .zero,
            sar: sar
        )
    }

    public var formattedStoredResolution: String {
        "\(storedWidth)×\(storedHeight)"
    }
}
