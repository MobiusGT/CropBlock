import Foundation

public enum ScanMode: String, Codable, Hashable, Sendable {
    case standard
    case deep
}

public struct SampleWindow: Codable, Hashable, Sendable, Identifiable {
    public let index: Int
    /// Target fraction of video duration (e.g. 0.20, 0.50, 0.80).
    public let percentage: Double
    public let startTime: Double
    public let duration: Double

    public var id: Int { index }

    public init(index: Int, percentage: Double, startTime: Double, duration: Double) {
        self.index = index
        self.percentage = percentage
        self.startTime = startTime
        self.duration = duration
    }

    public var label: String {
        "\(Int((percentage * 100).rounded()))%"
    }
}

public struct CropSample: Codable, Hashable, Sendable, Identifiable {
    public let window: SampleWindow
    public let detectedRect: CropRect?
    public let isAllBlack: Bool
    public var previewImagePath: String?

    public var id: Int { window.index }

    public init(
        window: SampleWindow,
        detectedRect: CropRect?,
        isAllBlack: Bool = false,
        previewImagePath: String? = nil
    ) {
        self.window = window
        self.detectedRect = detectedRect
        self.isAllBlack = isAllBlack
        self.previewImagePath = previewImagePath
    }
}

public struct VariableARInfo: Codable, Hashable, Sendable {
    public let widthSpread: Int
    public let heightSpread: Int
    public let thresholdWidth: Int
    public let thresholdHeight: Int

    public init(widthSpread: Int, heightSpread: Int, thresholdWidth: Int, thresholdHeight: Int) {
        self.widthSpread = widthSpread
        self.heightSpread = heightSpread
        self.thresholdWidth = thresholdWidth
        self.thresholdHeight = thresholdHeight
    }
}

/// Captures framing inconsistencies detected across samples, including subtle film-transfer
/// gate weave / edge jitter (below Variable AR) and all-black sample windows.
public struct FramingVarianceInfo: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case variableAR
        case edgeJitter
        case blackSamples
    }

    public let kind: Kind
    /// Maximum cross-sample spread (in pixels) across edges or active width/height.
    public let maxEdgeShift: Int
    /// Number of sampled windows that returned only pure-black frames.
    public let blackSampleCount: Int

    public init(kind: Kind, maxEdgeShift: Int, blackSampleCount: Int) {
        self.kind = kind
        self.maxEdgeShift = maxEdgeShift
        self.blackSampleCount = blackSampleCount
    }
}

public struct CropDetectionResult: Codable, Hashable, Sendable {
    public let scanMode: ScanMode
    public let isFullVideoSinglePass: Bool
    public let samples: [CropSample]
    public let unionRect: CropRect?
    public let proposedInsets: CropInsets
    public let variableAR: VariableARInfo?
    public let framingVariance: FramingVarianceInfo?
    public let allSamplesBlack: Bool

    public init(
        scanMode: ScanMode = .standard,
        isFullVideoSinglePass: Bool = false,
        samples: [CropSample],
        unionRect: CropRect?,
        proposedInsets: CropInsets,
        variableAR: VariableARInfo?,
        framingVariance: FramingVarianceInfo? = nil,
        allSamplesBlack: Bool
    ) {
        self.scanMode = scanMode
        self.isFullVideoSinglePass = isFullVideoSinglePass
        self.samples = samples
        self.unionRect = unionRect
        self.proposedInsets = proposedInsets
        self.variableAR = variableAR
        self.framingVariance = framingVariance
        self.allSamplesBlack = allSamplesBlack
    }

    public var hasBars: Bool { !proposedInsets.isZero }
    public var hasVariableAR: Bool { variableAR != nil }
    public var isDeepScanned: Bool { scanMode == .deep }

    /// Recommends a Deep Scan when a standard scan observed framing variance (Variable AR,
    /// ≥4 px film-transfer edge jitter, or all-black sample windows).
    public var shouldSuggestDeepScan: Bool {
        guard scanMode == .standard else { return false }
        return hasVariableAR || framingVariance != nil || allSamplesBlack
    }

    /// Subset of samples that carry extracted preview frames for the compact HUD switcher.
    /// Falls back to all samples if no previews were extracted (e.g., synthetic/no-image state).
    public var previewableSamples: [CropSample] {
        let withPreviews = samples.filter { $0.previewImagePath != nil }
        if !withPreviews.isEmpty {
            return withPreviews
        }
        return Array(samples.prefix(5))
    }

    /// Concise metadata label when this file has been Deep Scanned.
    public var deepScanBadgeLabel: String? {
        guard scanMode == .deep else { return nil }
        if isFullVideoSinglePass {
            return "Deep Scanned · Full Video"
        }
        return "Deep Scanned · \(samples.count) samples"
    }
}
