import Foundation

public enum CropBackendID: String, Codable, Hashable, Sendable, CaseIterable {
    case mkvHeader = "mkv-header"
    // Reserved for Milestone 3: H.264/HEVC SPS bitstream cropping (`h264_metadata` / `hevc_metadata`)
    case bitstreamMetadata = "bitstream-metadata"

    public var displayName: String {
        switch self {
        case .mkvHeader: "Matroska Header (mkvpropedit)"
        case .bitstreamMetadata: "H.264/HEVC Bitstream (Future)"
        }
    }
}

public struct HeaderPropertyChange: Codable, Hashable, Sendable, Identifiable {
    public let property: String
    public let before: String
    public let after: String
    public let changed: Bool

    public var id: String { property }

    public init(property: String, before: String, after: String, changed: Bool) {
        self.property = property
        self.before = before
        self.after = after
        self.changed = changed
    }
}

public struct CropApplyPlan: Codable, Hashable, Sendable {
    public let backendID: CropBackendID
    public let storedWidth: Int
    public let storedHeight: Int
    public let insets: CropInsets
    public let displayDimensions: DisplayDimensions
    public let sar: SampleAspectRatio
    public let changes: [HeaderPropertyChange]

    public init(
        backendID: CropBackendID,
        storedWidth: Int,
        storedHeight: Int,
        insets: CropInsets,
        displayDimensions: DisplayDimensions,
        sar: SampleAspectRatio,
        changes: [HeaderPropertyChange]
    ) {
        self.backendID = backendID
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.insets = insets
        self.displayDimensions = displayDimensions
        self.sar = sar
        self.changes = changes
    }

    public var croppedPixelWidth: Int { insets.croppedWidth(for: storedWidth) }
    public var croppedPixelHeight: Int { insets.croppedHeight(for: storedHeight) }
    public var formattedCroppedPixels: String { "\(croppedPixelWidth)×\(croppedPixelHeight)" }
}

/// Persisted snapshot of a file's original Matroska header prior to Crop Block edits.
public struct EditReceipt: Codable, Hashable, Sendable, Identifiable {
    public var id: String { canonicalPath }
    public let canonicalPath: String
    public let fileSize: Int64
    public let backendID: CropBackendID
    public let originalHeader: MatroskaVideoHeader
    public let appliedInsets: CropInsets
    public let appliedDisplay: DisplayDimensions
    public let appliedAt: Date

    public init(
        canonicalPath: String,
        fileSize: Int64,
        backendID: CropBackendID,
        originalHeader: MatroskaVideoHeader,
        appliedInsets: CropInsets,
        appliedDisplay: DisplayDimensions,
        appliedAt: Date = Date()
    ) {
        self.canonicalPath = canonicalPath
        self.fileSize = fileSize
        self.backendID = backendID
        self.originalHeader = originalHeader
        self.appliedInsets = appliedInsets
        self.appliedDisplay = appliedDisplay
        self.appliedAt = appliedAt
    }
}
