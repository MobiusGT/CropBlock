import Foundation

/// Pure, deterministic geometry math for standard & Deep Scan scheduling, union bounding boxes,
/// MKV edge offsets, anamorphic SAR display dimensions, Variable AR & film-transfer variance guards,
/// and representative preview frame selection.
public enum CropCalculator {

    /// Start and end tail fractions skipped by Deep Scan to avoid black intros and end credits.
    public static let deepScanStartTailFraction: Double = 0.05
    public static let deepScanEndTailFraction: Double = 0.08
    /// Minimum cross-sample edge/size variance (px) that triggers a film-transfer Deep Scan suggestion.
    public static let framingJitterThresholdPixels: Int = 4

    /// Builds clamped multi-timestamp sampling windows across a video's duration (Standard Scan).
    public static func sampleWindows(duration: Double, settings: DetectionSettings) -> [SampleWindow] {
        guard duration > 0 else {
            return [SampleWindow(index: 0, percentage: 0.0, startTime: 0, duration: settings.sampleDurationSeconds)]
        }

        // Very short clips: scan the entire clip once from 0s.
        if duration <= settings.sampleDurationSeconds + 1.0 {
            return [SampleWindow(index: 0, percentage: 0.5, startTime: 0, duration: max(0.5, duration))]
        }

        let perSampleDuration = min(settings.sampleDurationSeconds, max(1.0, duration / Double(settings.samplePercentages.count)))
        let maxStart = max(0, duration - perSampleDuration)

        return settings.samplePercentages.enumerated().map { idx, pct in
            let centeredStart = max(0, min(maxStart, duration * pct - perSampleDuration / 2.0))
            return SampleWindow(
                index: idx,
                percentage: pct,
                startTime: (centeredStart * 100).rounded() / 100,
                duration: (perSampleDuration * 100).rounded() / 100
            )
        }
    }

    /// Computes the duration-scaled Deep Scan interval count:
    /// - `duration <= 25 min`: 10 intervals
    /// - `duration > 25 min`: `10 + ceil((durationMinutes - 25) / 15)`
    public static func deepScanIntervalCount(durationSeconds: Double) -> Int {
        let baseSeconds = 25.0 * 60.0 // 1500 s
        guard durationSeconds > baseSeconds + 1e-6 else {
            return 10
        }
        let extraSeconds = durationSeconds - baseSeconds
        // Tiny epsilon prevents exact multiples (e.g., 40.0 min) from bumping due to IEEE-754 rounding.
        let extraBlocks = Int(ceil((extraSeconds - 1e-6) / (15.0 * 60.0)))
        return 10 + max(1, extraBlocks)
    }

    /// Builds evenly spaced, non-overlapping Deep Scan windows across the usable timeline
    /// (skipping 5% start / 8% end tails), or falls back to a full-video single pass when the
    /// video is too short to fit `intervals × sampleDuration` without overlap.
    public static func deepScanWindows(
        duration: Double,
        settings: DetectionSettings
    ) -> (windows: [SampleWindow], isFullVideoSinglePass: Bool) {
        let sampleDuration = settings.sampleDurationSeconds
        guard duration > 0 else {
            return ([SampleWindow(index: 0, percentage: 0.5, startTime: 0, duration: sampleDuration)], true)
        }

        let intervalCount = deepScanIntervalCount(durationSeconds: duration)
        let totalSampleTime = Double(intervalCount) * sampleDuration

        // Short videos (<= intervals * sampleDuration): scan 100% of frames in one fast pass.
        if duration <= totalSampleTime {
            let full = SampleWindow(
                index: 0,
                percentage: 0.5,
                startTime: 0,
                duration: (duration * 100).rounded() / 100
            )
            return ([full], true)
        }

        // Skip 5% start and 8% end tails when usable duration fits all non-overlapping intervals;
        // otherwise smoothly tighten tail margins (still guaranteed non-overlapping).
        let usableFraction = 1.0 - deepScanStartTailFraction - deepScanEndTailFraction
        let usableStart: Double
        let usableEnd: Double
        if duration * usableFraction >= totalSampleTime {
            usableStart = duration * deepScanStartTailFraction
            usableEnd = duration * (1.0 - deepScanEndTailFraction)
        } else {
            let leftover = max(0, duration - totalSampleTime)
            usableStart = leftover * 0.4
            usableEnd = duration - leftover * 0.6
        }

        let lastStart = max(usableStart, usableEnd - sampleDuration)
        let step = intervalCount > 1 ? (lastStart - usableStart) / Double(intervalCount - 1) : 0

        let windows: [SampleWindow] = (0..<intervalCount).map { idx in
            let start = usableStart + Double(idx) * step
            let midpoint = min(duration, start + sampleDuration / 2.0)
            let pct = max(0.01, min(0.99, midpoint / duration))
            return SampleWindow(
                index: idx,
                percentage: pct,
                startTime: (start * 100).rounded() / 100,
                duration: (sampleDuration * 100).rounded() / 100
            )
        }
        return (windows, false)
    }

    /// Selects up to `maxCount` (default 5) representative sample indices for preview extraction
    /// so Deep Scan stays fast and the preview HUD stays compact.
    /// Prioritizes outlier/disagreeing frames (largest & smallest active rects) alongside evenly
    /// spaced timeline frames, returned in chronological order.
    public static func selectPreviewIndices(samples: [CropSample], maxCount: Int = 5) -> [Int] {
        guard !samples.isEmpty, maxCount > 0 else { return [] }
        if samples.count <= maxCount {
            return Array(0..<samples.count)
        }

        var chosen: Set<Int> = []

        // 1. Prioritize contrasting active rects (largest & smallest non-black area) so
        //    IMAX / Variable AR / film-transfer outlier frames are always inspectable.
        let scored = samples.enumerated().compactMap { idx, sample -> (index: Int, area: Int, height: Int, width: Int)? in
            guard !sample.isAllBlack, let rect = sample.detectedRect, rect.isValid else { return nil }
            return (idx, rect.width * rect.height, rect.height, rect.width)
        }

        if let maxItem = scored.max(by: { $0.area < $1.area }),
           let minItem = scored.min(by: { $0.area < $1.area }),
           maxItem.area != minItem.area {
            chosen.insert(maxItem.index)
            if chosen.count < maxCount {
                chosen.insert(minItem.index)
            }
        }

        // 2. Fill remaining slots with evenly distributed anchor positions across the timeline.
        if chosen.count < maxCount {
            let anchorPositions: [Int] = (0..<maxCount).map { slot in
                if maxCount == 1 { return samples.count / 2 }
                let frac = Double(slot) / Double(maxCount - 1)
                return Int((frac * Double(samples.count - 1)).rounded())
            }
            for anchor in anchorPositions where chosen.count < maxCount {
                chosen.insert(anchor)
            }
        }

        // 3. Fallback sweep if anchors collided with outlier indices.
        if chosen.count < maxCount {
            for idx in 0..<samples.count where chosen.count < maxCount {
                chosen.insert(idx)
            }
        }

        return chosen.sorted()
    }

    /// Computes the union bounding box across all valid samples, converts to even-pixel MKV insets,
    /// flags Variable AR on large aspect-ratio shifts, and records subtle film-transfer framing variance
    /// or all-black sample windows to power smart Deep Scan suggestions.
    public static func unionAndAnalyze(
        samples: [CropSample],
        frameWidth: Int,
        frameHeight: Int,
        noiseFloor: Int = 4,
        scanMode: ScanMode = .standard,
        isFullVideoSinglePass: Bool = false
    ) -> CropDetectionResult {
        guard frameWidth > 0, frameHeight > 0 else {
            return CropDetectionResult(
                scanMode: scanMode,
                isFullVideoSinglePass: isFullVideoSinglePass,
                samples: samples,
                unionRect: nil,
                proposedInsets: .zero,
                variableAR: nil,
                framingVariance: nil,
                allSamplesBlack: true
            )
        }

        let blackSampleCount = samples.filter(\.isAllBlack).count

        let validRects = samples.compactMap { sample -> CropRect? in
            guard !sample.isAllBlack, let rect = sample.detectedRect, rect.isValid else { return nil }
            let clampedX = min(frameWidth, max(0, rect.x))
            let clampedY = min(frameHeight, max(0, rect.y))
            let clampedW = min(frameWidth - clampedX, max(0, rect.width))
            let clampedH = min(frameHeight - clampedY, max(0, rect.height))
            guard clampedW > 0, clampedH > 0 else { return nil }
            return CropRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
        }

        guard !validRects.isEmpty else {
            let variance = blackSampleCount > 0
                ? FramingVarianceInfo(kind: .blackSamples, maxEdgeShift: 0, blackSampleCount: blackSampleCount)
                : nil
            return CropDetectionResult(
                scanMode: scanMode,
                isFullVideoSinglePass: isFullVideoSinglePass,
                samples: samples,
                unionRect: nil,
                proposedInsets: .zero,
                variableAR: nil,
                framingVariance: variance,
                allSamplesBlack: true
            )
        }

        // Union bounding box: expands outward so a dark scene never causes over-cropping.
        let minX = validRects.map(\.x).min() ?? 0
        let minY = validRects.map(\.y).min() ?? 0
        let maxX = validRects.map(\.maxX).max() ?? frameWidth
        let maxY = validRects.map(\.maxY).max() ?? frameHeight

        let unionRect = CropRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let insets = insets(from: unionRect, frameWidth: frameWidth, frameHeight: frameHeight, noiseFloor: noiseFloor)

        // Variable AR & film-transfer framing variance checks across non-black samples.
        var variableAR: VariableARInfo?
        var maxEdgeShift = 0

        if validRects.count >= 2 {
            let widths = validRects.map(\.width)
            let heights = validRects.map(\.height)
            let lefts = validRects.map(\.x)
            let tops = validRects.map(\.y)
            let rights = validRects.map(\.maxX)
            let bottoms = validRects.map(\.maxY)

            let widthSpread = (widths.max() ?? 0) - (widths.min() ?? 0)
            let heightSpread = (heights.max() ?? 0) - (heights.min() ?? 0)
            let leftSpread = (lefts.max() ?? 0) - (lefts.min() ?? 0)
            let topSpread = (tops.max() ?? 0) - (tops.min() ?? 0)
            let rightSpread = (rights.max() ?? 0) - (rights.min() ?? 0)
            let bottomSpread = (bottoms.max() ?? 0) - (bottoms.min() ?? 0)
            maxEdgeShift = max(widthSpread, heightSpread, leftSpread, topSpread, rightSpread, bottomSpread)

            let thresholdW = max(16, Int((Double(frameWidth) * 0.03).rounded()))
            let thresholdH = max(16, Int((Double(frameHeight) * 0.03).rounded()))

            if widthSpread > thresholdW || heightSpread > thresholdH {
                variableAR = VariableARInfo(
                    widthSpread: widthSpread,
                    heightSpread: heightSpread,
                    thresholdWidth: thresholdW,
                    thresholdHeight: thresholdH
                )
            }
        }

        let framingVariance: FramingVarianceInfo?
        if variableAR != nil {
            framingVariance = FramingVarianceInfo(
                kind: .variableAR,
                maxEdgeShift: maxEdgeShift,
                blackSampleCount: blackSampleCount
            )
        } else if maxEdgeShift >= framingJitterThresholdPixels {
            framingVariance = FramingVarianceInfo(
                kind: .edgeJitter,
                maxEdgeShift: maxEdgeShift,
                blackSampleCount: blackSampleCount
            )
        } else if blackSampleCount > 0 {
            framingVariance = FramingVarianceInfo(
                kind: .blackSamples,
                maxEdgeShift: maxEdgeShift,
                blackSampleCount: blackSampleCount
            )
        } else {
            framingVariance = nil
        }

        return CropDetectionResult(
            scanMode: scanMode,
            isFullVideoSinglePass: isFullVideoSinglePass,
            samples: samples,
            unionRect: unionRect,
            proposedInsets: insets,
            variableAR: variableAR,
            framingVariance: framingVariance,
            allSamplesBlack: false
        )
    }

    /// Converts a `crop=w:h:x:y` rect into conservative even-pixel Matroska edge offsets.
    public static func insets(
        from rect: CropRect,
        frameWidth: Int,
        frameHeight: Int,
        noiseFloor: Int = 4
    ) -> CropInsets {
        guard frameWidth > 0, frameHeight > 0, rect.isValid else { return .zero }

        let rawLeft = max(0, min(frameWidth, rect.x))
        let rawTop = max(0, min(frameHeight, rect.y))
        let rawRight = max(0, min(frameWidth, frameWidth - rect.width - rect.x))
        let rawBottom = max(0, min(frameHeight, frameHeight - rect.height - rect.y))

        var left = floorEven(rawLeft)
        var right = floorEven(rawRight)
        var top = floorEven(rawTop)
        var bottom = floorEven(rawBottom)

        if left < noiseFloor { left = 0 }
        if right < noiseFloor { right = 0 }
        if top < noiseFloor { top = 0 }
        if bottom < noiseFloor { bottom = 0 }

        guard left + right < frameWidth, top + bottom < frameHeight else {
            return .zero
        }
        return CropInsets(left: left, right: right, top: top, bottom: bottom)
    }

    /// Clamps user-edited offsets to valid even pixels leaving at least 16×16 active video.
    public static func clampManualInsets(
        _ raw: CropInsets,
        frameWidth: Int,
        frameHeight: Int
    ) -> CropInsets {
        let minActive = min(16, min(frameWidth, frameHeight))
        var left = floorEven(max(0, raw.left))
        var right = floorEven(max(0, raw.right))
        var top = floorEven(max(0, raw.top))
        var bottom = floorEven(max(0, raw.bottom))

        let maxHorizontal = max(0, floorEven(frameWidth - minActive))
        if left + right > maxHorizontal {
            right = max(0, floorEven(maxHorizontal - left))
            if left + right > maxHorizontal {
                left = maxHorizontal
                right = 0
            }
        }

        let maxVertical = max(0, floorEven(frameHeight - minActive))
        if top + bottom > maxVertical {
            bottom = max(0, floorEven(maxVertical - top))
            if top + bottom > maxVertical {
                top = maxVertical
                bottom = 0
            }
        }

        return CropInsets(left: left, right: right, top: top, bottom: bottom)
    }

    /// Computes SAR-adjusted effective display dimensions for preview rendering and aspect-ratio display.
    public static func displayDimensions(
        storedWidth: Int,
        storedHeight: Int,
        insets: CropInsets,
        sar: SampleAspectRatio
    ) -> DisplayDimensions {
        let croppedW = max(1, storedWidth - insets.left - insets.right)
        let croppedH = max(1, storedHeight - insets.top - insets.bottom)

        if sar.isSquare {
            return DisplayDimensions(width: croppedW, height: croppedH, unit: 0)
        } else if sar.numerator > sar.denominator {
            let displayW = Int((Double(croppedW) * Double(sar.numerator) / Double(sar.denominator)).rounded())
            return DisplayDimensions(width: max(1, displayW), height: croppedH, unit: 0)
        } else {
            let displayH = Int((Double(croppedH) * Double(sar.denominator) / Double(sar.numerator)).rounded())
            return DisplayDimensions(width: croppedW, height: max(1, displayH), unit: 0)
        }
    }

    /// Resolves effective SAR from ffprobe, falling back to uncropped Matroska DisplayWidth/DisplayHeight if needed.
    public static func effectiveSAR(
        ffprobeSAR: SampleAspectRatio?,
        originalHeader: MatroskaVideoHeader,
        storedWidth: Int,
        storedHeight: Int
    ) -> SampleAspectRatio {
        if let ffprobeSAR {
            return ffprobeSAR
        }
        if !originalHeader.hasNonZeroCrop,
           (originalHeader.displayUnit ?? 0) == 0,
           let dw = originalHeader.displayWidth, dw > 0,
           let dh = originalHeader.displayHeight, dh > 0,
           storedWidth > 0, storedHeight > 0 {
            return SampleAspectRatio(numerator: dw * storedHeight, denominator: storedWidth * dh)
        }
        return .square
    }

    private static func floorEven(_ value: Int) -> Int {
        value - (value % 2)
    }
}
