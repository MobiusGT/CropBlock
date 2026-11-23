import Foundation
import Testing
@testable import CropBlockKit

@Suite("DetectionSettings validation and persistence")
struct DetectionSettingsTests {
    @Test("Clamps out-of-range values cleanly")
    func validatesBounds() {
        let clamped = DetectionSettings(
            samplePercentages: [-0.5, 1.5, 0.50],
            sampleDurationSeconds: 120,
            cropDetectLimit: 999,
            noiseFloorPixels: 5,
            maxConcurrentScans: 16,
            autoScanOnAdd: false
        )
        #expect(clamped.samplePercentages == [0.01, 0.50, 0.99])
        #expect(clamped.sampleDurationSeconds == 60)
        #expect(clamped.cropDetectLimit == 255)
        #expect(clamped.noiseFloorPixels == 4)
        #expect(clamped.maxConcurrentScans == 4)
        #expect(clamped.autoScanOnAdd == false)
    }

    @Test("Encodes and decodes round-trip cleanly")
    func jsonRoundTrip() {
        let custom = DetectionSettings(
            samplePercentages: [0.15, 0.55, 0.85],
            sampleDurationSeconds: 12,
            cropDetectLimit: 28,
            noiseFloorPixels: 6,
            maxConcurrentScans: 3,
            autoScanOnAdd: false
        )
        let data = custom.encode()
        let loaded = DetectionSettings.decode(from: data)
        #expect(loaded == custom)
        #expect(DetectionSettings.decode(from: nil) == .default)
    }
}
