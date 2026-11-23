import Foundation

/// User-configurable detection and scanning settings.
public struct DetectionSettings: Codable, Hashable, Sendable {
    /// Percentages across video duration to sample (0.01...0.99).
    public var samplePercentages: [Double]
    /// Seconds to scan at each sample timestamp.
    public var sampleDurationSeconds: Double
    /// `cropdetect` black pixel luma threshold (0...255).
    public var cropDetectLimit: Int
    /// Minimum bar size in pixels before proposing a crop (filters 2 px compression noise).
    public var noiseFloorPixels: Int
    /// Maximum number of concurrent background file scans (1...4).
    public var maxConcurrentScans: Int
    /// Automatically start scanning files as soon as they enter the queue.
    public var autoScanOnAdd: Bool

    public static let `default` = DetectionSettings(
        samplePercentages: [0.20, 0.50, 0.80],
        sampleDurationSeconds: 10,
        cropDetectLimit: 24,
        noiseFloorPixels: 4,
        maxConcurrentScans: 2,
        autoScanOnAdd: true
    )

    public init(
        samplePercentages: [Double] = [0.20, 0.50, 0.80],
        sampleDurationSeconds: Double = 10,
        cropDetectLimit: Int = 24,
        noiseFloorPixels: Int = 4,
        maxConcurrentScans: Int = 2,
        autoScanOnAdd: Bool = true
    ) {
        let cleaned = samplePercentages
            .map { min(0.99, max(0.01, $0)) }
            .sorted()
        self.samplePercentages = cleaned.isEmpty ? [0.20, 0.50, 0.80] : cleaned
        self.sampleDurationSeconds = min(60, max(1, sampleDurationSeconds))
        self.cropDetectLimit = min(255, max(0, cropDetectLimit))
        self.noiseFloorPixels = min(32, max(0, noiseFloorPixels))
        self.maxConcurrentScans = min(4, max(1, maxConcurrentScans))
        self.autoScanOnAdd = autoScanOnAdd
    }
}
