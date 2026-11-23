import Foundation

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

public struct CropDetectionResult: Codable, Hashable, Sendable {
    public let samples: [CropSample]
    public let unionRect: CropRect?
    public let proposedInsets: CropInsets
    public let variableAR: VariableARInfo?
    public let allSamplesBlack: Bool

    public init(
        samples: [CropSample],
        unionRect: CropRect?,
        proposedInsets: CropInsets,
        variableAR: VariableARInfo?,
        allSamplesBlack: Bool
    ) {
        self.samples = samples
        self.unionRect = unionRect
        self.proposedInsets = proposedInsets
        self.variableAR = variableAR
        self.allSamplesBlack = allSamplesBlack
    }

    public var hasBars: Bool { !proposedInsets.isZero }
    public var hasVariableAR: Bool { variableAR != nil }
}
