import Foundation
import Testing
@testable import CropBlockKit

@Suite("Deep Scan scheduling, preview selection, framing variance, and batch planner")
struct DeepScanTests {

    @Test(
        "Duration-scaled Deep Scan interval count matches formula across all boundaries",
        arguments: [
            (5.0, 10),
            (25.0, 10),
            (26.0, 11),
            (40.0, 11),
            (41.0, 12),
            (55.0, 12),
            (56.0, 13),
            (90.0, 15),
            (120.0, 17),
        ]
    )
    func deepScanIntervalCountFormula(durationMinutes: Double, expectedIntervals: Int) {
        let count = CropCalculator.deepScanIntervalCount(durationSeconds: durationMinutes * 60.0)
        #expect(count == expectedIntervals)
    }

    @Test("Short videos fall back to a single full-video pass with zero overlap")
    func shortVideoFullSinglePass() {
        let settings = DetectionSettings.default // 10s sample duration -> 10 * 10 = 100s threshold
        let (windows60, singlePass60) = CropCalculator.deepScanWindows(duration: 60, settings: settings)
        #expect(singlePass60)
        #expect(windows60.count == 1)
        #expect(windows60[0].startTime == 0)
        #expect(windows60[0].duration == 60)

        let (windows100, singlePass100) = CropCalculator.deepScanWindows(duration: 100, settings: settings)
        #expect(singlePass100)
        #expect(windows100.count == 1)
    }

    @Test("Feature-length Deep Scan windows skip 5% start / 8% end tails and never overlap")
    func featureLengthDeepScanWindows() {
        let duration = 120.0 * 60.0 // 7200 s -> 17 intervals
        let (windows, isSinglePass) = CropCalculator.deepScanWindows(duration: duration, settings: .default)
        #expect(!isSinglePass)
        #expect(windows.count == 17)

        let minStart = duration * 0.05
        let maxEnd = duration * 0.92
        #expect(windows.first!.startTime >= minStart - 0.01)
        #expect(windows.last!.startTime + windows.last!.duration <= maxEnd + 0.01)

        // Strictly non-overlapping and monotonically ordered
        for (a, b) in zip(windows, windows.dropFirst()) {
            #expect(a.startTime + a.duration <= b.startTime + 0.01)
        }
    }

    @Test("Tight-fit duration (105s with 10x10s) still yields 10 non-overlapping windows inside duration")
    func tightDurationNonOverlapping() {
        let (windows, isSinglePass) = CropCalculator.deepScanWindows(duration: 105, settings: .default)
        #expect(!isSinglePass)
        #expect(windows.count == 10)
        #expect(windows.first!.startTime >= 0)
        #expect(windows.last!.startTime + windows.last!.duration <= 105.01)
        for (a, b) in zip(windows, windows.dropFirst()) {
            #expect(a.startTime + a.duration <= b.startTime + 0.01)
        }
    }

    @Test("Representative preview selector caps at 5 frames and preserves outlier Variable AR frames in order")
    func previewSelectionPrioritizesOutliers() {
        // 15 samples: all 1920x800 except sample index 6 (IMAX 1920x1080) and sample index 11 (dark tight 1920x780)
        let samples = (0..<15).map { idx -> CropSample in
            let rect: CropRect
            if idx == 6 {
                rect = CropRect(x: 0, y: 0, width: 1920, height: 1080)
            } else if idx == 11 {
                rect = CropRect(x: 0, y: 150, width: 1920, height: 780)
            } else {
                rect = CropRect(x: 0, y: 140, width: 1920, height: 800)
            }
            return CropSample(
                window: SampleWindow(index: idx, percentage: Double(idx + 1) / 16.0, startTime: Double(idx) * 300, duration: 10),
                detectedRect: rect
            )
        }

        let selected = CropCalculator.selectPreviewIndices(samples: samples, maxCount: 5)
        #expect(selected.count == 5)
        #expect(selected == selected.sorted())
        #expect(Set(selected).count == 5)
        #expect(selected.contains(6))  // largest active area (IMAX)
        #expect(selected.contains(11)) // smallest active area (tightest bars)
    }

    @Test("Subtle film-transfer edge jitter (4–16 px) triggers Deep Scan suggestion without blocking as Variable AR")
    func filmTransferEdgeJitterSuggestsDeepScan() {
        let samples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.2, startTime: 600, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
            // 8px framing shift (gate weave / film transfer drift — below 32px Variable AR threshold)
            CropSample(window: SampleWindow(index: 1, percentage: 0.5, startTime: 1500, duration: 10),
                       detectedRect: CropRect(x: 0, y: 144, width: 1920, height: 792)),
            CropSample(window: SampleWindow(index: 2, percentage: 0.8, startTime: 2400, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
        ]
        let standard = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080, scanMode: .standard)
        #expect(!standard.hasVariableAR)
        #expect(standard.framingVariance?.kind == .edgeJitter)
        #expect(standard.framingVariance?.maxEdgeShift == 8)
        #expect(standard.shouldSuggestDeepScan)
        #expect(standard.proposedInsets == CropInsets(left: 0, right: 0, top: 140, bottom: 140))

        // After Deep Scan completes, suggestion clears while union stays safe
        let deep = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080, scanMode: .deep)
        #expect(deep.isDeepScanned)
        #expect(!deep.shouldSuggestDeepScan)
        #expect(deep.deepScanBadgeLabel == "Deep Scanned · 3 samples")
    }

    @Test("Single all-black sample during standard scan suggests Deep Scan")
    func blackSampleSuggestsDeepScan() {
        let samples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.2, startTime: 600, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
            CropSample(window: SampleWindow(index: 1, percentage: 0.5, startTime: 1500, duration: 10),
                       detectedRect: nil, isAllBlack: true),
            CropSample(window: SampleWindow(index: 2, percentage: 0.8, startTime: 2400, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
        ]
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080, scanMode: .standard)
        #expect(!result.hasVariableAR)
        #expect(result.framingVariance?.kind == .blackSamples)
        #expect(result.framingVariance?.blackSampleCount == 1)
        #expect(result.shouldSuggestDeepScan)
    }

    @Test("Consistent standard samples (<= 2px variance, no black samples) do NOT suggest Deep Scan")
    func consistentFramingDoesNotSuggestDeepScan() {
        let samples = [0.2, 0.5, 0.8].enumerated().map { idx, pct in
            CropSample(
                window: SampleWindow(index: idx, percentage: pct, startTime: pct * 3600, duration: 10),
                detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)
            )
        }
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080, scanMode: .standard)
        #expect(result.framingVariance == nil)
        #expect(!result.shouldSuggestDeepScan)
    }

    @Test("DeepScanBatchPlanner skips already-Cropped and already-Deep-Scanned items")
    func deepScanBatchEligibility() {
        let pending = UUID()
        let detected = UUID()
        let detectedAlreadyDeep = UUID()
        let variableAR = UUID()
        let noBars = UUID()
        let cropped = UUID()
        let errored = UUID()
        let scanning = UUID()

        let candidates: [DeepScanCandidate] = [
            DeepScanCandidate(id: pending, status: .pending, isDeepScanned: false),
            DeepScanCandidate(id: detected, status: .detected, isDeepScanned: false),
            DeepScanCandidate(id: detectedAlreadyDeep, status: .detected, isDeepScanned: true),
            DeepScanCandidate(id: variableAR, status: .variableAR, isDeepScanned: false),
            DeepScanCandidate(id: noBars, status: .noBars, isDeepScanned: false),
            DeepScanCandidate(id: cropped, status: .cropped, isDeepScanned: false),
            DeepScanCandidate(id: errored, status: .error, isDeepScanned: false),
            DeepScanCandidate(id: scanning, status: .scanning, isDeepScanned: false),
        ]

        let selected = DeepScanBatchPlanner.eligibleIDs(from: candidates)
        #expect(selected == [pending, detected, variableAR, noBars, errored])
    }
}
