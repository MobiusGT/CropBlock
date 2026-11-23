import Foundation
import Testing
@testable import CropBlockKit

@Suite("CropCalculator geometry, SAR, and Variable AR math")
struct CropCalculatorTests {

    @Test("Standard 16:9 full-frame video reports no bars")
    func standard16x9NoBars() {
        let samples = [0.2, 0.5, 0.8].enumerated().map { idx, pct in
            CropSample(
                window: SampleWindow(index: idx, percentage: pct, startTime: pct * 3600, duration: 10),
                detectedRect: CropRect(x: 0, y: 0, width: 1920, height: 1080)
            )
        }
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(!result.hasBars)
        #expect(result.proposedInsets == .zero)
        #expect(!result.hasVariableAR)
        #expect(!result.allSamplesBlack)
    }

    @Test("Ultrawide 2.39:1 letterbox on 1080p produces exact L/R/T/B and 2.40:1 display size")
    func ultrawide1080pLetterbox() {
        let samples = [0.2, 0.5, 0.8].enumerated().map { idx, pct in
            CropSample(
                window: SampleWindow(index: idx, percentage: pct, startTime: pct * 7200, duration: 10),
                detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)
            )
        }
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(result.proposedInsets == CropInsets(left: 0, right: 0, top: 140, bottom: 140))
        #expect(!result.hasVariableAR)

        let display = CropCalculator.displayDimensions(
            storedWidth: 1920,
            storedHeight: 1080,
            insets: result.proposedInsets,
            sar: .square
        )
        #expect(display.width == 1920)
        #expect(display.height == 800)
        #expect(display.unit == 0)
        #expect(display.formattedAspectRatio == "2.40:1")
    }

    @Test("4:3 pillarbox inside 1080p computes left and right offsets")
    func pillarbox4x3Inside1080p() {
        let samples = [0.2, 0.5, 0.8].enumerated().map { idx, pct in
            CropSample(
                window: SampleWindow(index: idx, percentage: pct, startTime: pct * 1800, duration: 10),
                detectedRect: CropRect(x: 240, y: 0, width: 1440, height: 1080)
            )
        }
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(result.proposedInsets == CropInsets(left: 240, right: 240, top: 0, bottom: 0))

        let display = CropCalculator.displayDimensions(
            storedWidth: 1920,
            storedHeight: 1080,
            insets: result.proposedInsets,
            sar: .square
        )
        #expect(display.width == 1440)
        #expect(display.height == 1080)
        #expect(display.formattedAspectRatio == "1.33:1")
    }

    @Test("Union bounding box expands outward so dark scenes never cause over-cropping")
    func darkSceneUnionNeverOverCrops() {
        let samples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.2, startTime: 600, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
            // Dark middle scene looks smaller (1920x788): within 3% threshold, union keeps 800
            CropSample(window: SampleWindow(index: 1, percentage: 0.5, startTime: 1500, duration: 10),
                       detectedRect: CropRect(x: 0, y: 146, width: 1920, height: 788)),
            CropSample(window: SampleWindow(index: 2, percentage: 0.8, startTime: 2400, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
        ]
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(result.proposedInsets == CropInsets(left: 0, right: 0, top: 140, bottom: 140))
        #expect(!result.hasVariableAR)
    }

    @Test("Wide anamorphic SAR scales display-width accurately without stretching")
    func wideAnamorphicSAR() {
        // NTSC 16:9 DVD: 720x480 SAR 32:27 with 60px top/bottom bars -> cropped 720x360 -> DW 853 x DH 360
        let ntsc = CropCalculator.displayDimensions(
            storedWidth: 720,
            storedHeight: 480,
            insets: CropInsets(left: 0, right: 0, top: 60, bottom: 60),
            sar: SampleAspectRatio(numerator: 32, denominator: 27)
        )
        #expect(ntsc.width == 853)
        #expect(ntsc.height == 360)
        #expect(ntsc.unit == 0)

        // PAL 16:9 DVD: 720x576 SAR 64:45 with 72px top/bottom bars -> cropped 720x432 -> DW 1024 x DH 432
        let pal = CropCalculator.displayDimensions(
            storedWidth: 720,
            storedHeight: 576,
            insets: CropInsets(left: 0, right: 0, top: 72, bottom: 72),
            sar: SampleAspectRatio(numerator: 64, denominator: 45)
        )
        #expect(pal.width == 1024)
        #expect(pal.height == 432)

        // HDV 1440x1080 SAR 4:3 with 140px top/bottom -> DW 1920 x DH 800 (2.40:1)
        let hdv = CropCalculator.displayDimensions(
            storedWidth: 1440,
            storedHeight: 1080,
            insets: CropInsets(left: 0, right: 0, top: 140, bottom: 140),
            sar: SampleAspectRatio(numerator: 4, denominator: 3)
        )
        #expect(hdv.width == 1920)
        #expect(hdv.height == 800)
        #expect(hdv.formattedAspectRatio == "2.40:1")
    }

    @Test("Tall anamorphic SAR preserves width and scales display-height upward")
    func tallAnamorphicSAR() {
        // NTSC 4:3 DVD: 720x480 SAR 8:9 with 60px top/bottom bars -> cropped 720x360 -> DW 720 x DH 405 (1.78:1)
        let tall = CropCalculator.displayDimensions(
            storedWidth: 720,
            storedHeight: 480,
            insets: CropInsets(left: 0, right: 0, top: 60, bottom: 60),
            sar: SampleAspectRatio(numerator: 8, denominator: 9)
        )
        #expect(tall.width == 720)
        #expect(tall.height == 405)
        #expect(tall.formattedAspectRatio == "1.78:1")
    }

    @Test("Effective SAR falls back to uncropped MKV DisplayWidth/Height when ffprobe SAR is N/A")
    func effectiveSARFallbackFromMKVHeader() {
        let header = MatroskaVideoHeader(
            pixelWidth: 720,
            pixelHeight: 480,
            displayWidth: 854,
            displayHeight: 480,
            displayUnit: 0
        )
        let sar = CropCalculator.effectiveSAR(
            ffprobeSAR: SampleAspectRatio.parse("N/A"),
            originalHeader: header,
            storedWidth: 720,
            storedHeight: 480
        )
        #expect(!sar.isSquare)
        #expect(abs(sar.ratio - (854.0 / 720.0)) < 0.001)
    }

    @Test("Mixed aspect ratio (IMAX vs 2.39:1) triggers Variable AR warning")
    func mixedAspectRatioIMAXWarning() {
        let samples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.2, startTime: 1000, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
            // IMAX full-frame sequence
            CropSample(window: SampleWindow(index: 1, percentage: 0.5, startTime: 3000, duration: 10),
                       detectedRect: CropRect(x: 0, y: 0, width: 1920, height: 1080)),
            CropSample(window: SampleWindow(index: 2, percentage: 0.8, startTime: 5000, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
        ]
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(result.hasVariableAR)
        #expect(result.variableAR?.heightSpread == 280)
        // Union safely covers the largest active area (1920x1080) so IMAX scenes aren't chopped
        #expect(result.proposedInsets == .zero)
    }

    @Test("Mixed 1.90:1 IMAX vs 2.39:1 triggers Variable AR while proposing conservative 1.90:1 union")
    func mixedIMAX190VsScope() {
        let samples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.2, startTime: 1000, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
            CropSample(window: SampleWindow(index: 1, percentage: 0.5, startTime: 3000, duration: 10),
                       detectedRect: CropRect(x: 0, y: 34, width: 1920, height: 1012)),
            CropSample(window: SampleWindow(index: 2, percentage: 0.8, startTime: 5000, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800)),
        ]
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(result.hasVariableAR)
        #expect(result.variableAR?.heightSpread == 212)
        #expect(result.proposedInsets == CropInsets(left: 0, right: 0, top: 34, bottom: 34))
    }

    @Test("Odd crop rects round conservatively outward to even pixels and apply noise floor")
    func oddRoundingAndNoiseFloor() {
        // Odd 1px horizontal edge -> floored to 0; 141px top -> floored to 140; 140px bottom -> 140
        let insets = CropCalculator.insets(
            from: CropRect(x: 1, y: 141, width: 1918, height: 799),
            frameWidth: 1920,
            frameHeight: 1080,
            noiseFloor: 4
        )
        #expect(insets == CropInsets(left: 0, right: 0, top: 140, bottom: 140))

        // 2px noise on all edges suppressed to zero under noiseFloor = 4
        let jitter = CropCalculator.insets(
            from: CropRect(x: 2, y: 2, width: 1916, height: 1076),
            frameWidth: 1920,
            frameHeight: 1080,
            noiseFloor: 4
        )
        #expect(jitter == .zero)
    }

    @Test("All-black samples never produce degenerate 0x0 crop")
    func allBlackSamplesGuarded() {
        let samples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.2, startTime: 10, duration: 10), detectedRect: nil, isAllBlack: true),
            CropSample(window: SampleWindow(index: 1, percentage: 0.5, startTime: 30, duration: 10), detectedRect: nil, isAllBlack: true),
        ]
        let result = CropCalculator.unionAndAnalyze(samples: samples, frameWidth: 1920, frameHeight: 1080)
        #expect(result.allSamplesBlack)
        #expect(result.proposedInsets == .zero)
        #expect(!result.hasBars)
    }

    @Test("Sample window scheduling handles feature-length and short clips cleanly")
    func sampleWindowScheduling() {
        let longWindows = CropCalculator.sampleWindows(duration: 7200, settings: .default)
        #expect(longWindows.count == 3)
        #expect(longWindows[0].label == "20%")
        #expect(longWindows[1].label == "50%")
        #expect(longWindows[2].label == "80%")
        #expect(longWindows.allSatisfy { $0.duration == 10 && $0.startTime + $0.duration <= 7200 })

        let shortWindows = CropCalculator.sampleWindows(duration: 6, settings: .default)
        #expect(shortWindows.count == 1)
        #expect(shortWindows[0].startTime == 0)
        #expect(shortWindows[0].duration == 6)
    }

    @Test("Manual inset clamping enforces even values and minimum active picture")
    func manualInsetClamping() {
        let clamped = CropCalculator.clampManualInsets(
            CropInsets(left: 1915, right: 100, top: 139, bottom: -4),
            frameWidth: 1920,
            frameHeight: 1080
        )
        #expect(clamped.left % 2 == 0)
        #expect(clamped.right % 2 == 0)
        #expect(clamped.top == 138)
        #expect(clamped.bottom == 0)
        #expect(clamped.croppedWidth(for: 1920) >= 16)
        #expect(clamped.croppedHeight(for: 1080) >= 16)
    }
}
