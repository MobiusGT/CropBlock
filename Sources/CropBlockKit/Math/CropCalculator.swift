import Foundation

/// Pure, deterministic geometry math for sample scheduling, union bounding boxes,
/// MKV edge offsets, anamorphic SAR display dimensions, and Variable AR guards.
public enum CropCalculator {

    /// Builds clamped multi-timestamp sampling windows across a video's duration.
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

    /// Computes the union bounding box across all valid samples, converts to even-pixel MKV insets,
    /// and flags Variable AR when samples disagree significantly on active width or height.
    public static func unionAndAnalyze(
        samples: [CropSample],
        frameWidth: Int,
        frameHeight: Int,
        noiseFloor: Int = 4
    ) -> CropDetectionResult {
        guard frameWidth > 0, frameHeight > 0 else {
            return CropDetectionResult(
                samples: samples,
                unionRect: nil,
                proposedInsets: .zero,
                variableAR: nil,
                allSamplesBlack: true
            )
        }

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
            return CropDetectionResult(
                samples: samples,
                unionRect: nil,
                proposedInsets: .zero,
                variableAR: nil,
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

        // Variable AR guard: compare active width & height spread across non-black samples.
        var variableAR: VariableARInfo?
        if validRects.count >= 2 {
            let widths = validRects.map(\.width)
            let heights = validRects.map(\.height)
            let widthSpread = (widths.max() ?? 0) - (widths.min() ?? 0)
            let heightSpread = (heights.max() ?? 0) - (heights.min() ?? 0)
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

        return CropDetectionResult(
            samples: samples,
            unionRect: unionRect,
            proposedInsets: insets,
            variableAR: variableAR,
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

        // Floor conservatively to even numbers (round outward, never inward into active picture).
        var left = floorEven(rawLeft)
        var right = floorEven(rawRight)
        var top = floorEven(rawTop)
        var bottom = floorEven(rawBottom)

        // Suppress tiny compression jitter on full-frame videos.
        if left < noiseFloor { left = 0 }
        if right < noiseFloor { right = 0 }
        if top < noiseFloor { top = 0 }
        if bottom < noiseFloor { bottom = 0 }

        // Never produce a degenerate crop that removes the entire width or height.
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

    /// Computes SAR-adjusted Matroska `display-width` and `display-height` (`display-unit = 0`).
    /// Preserves full pixel precision on the tighter axis and scales the anamorphic axis upward.
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
            // Wide pixels (e.g., 32:27 NTSC 16:9 DVD, 4:3 HDV): preserve height, scale width up.
            let displayW = Int((Double(croppedW) * Double(sar.numerator) / Double(sar.denominator)).rounded())
            return DisplayDimensions(width: max(1, displayW), height: croppedH, unit: 0)
        } else {
            // Tall pixels (e.g., 8:9 NTSC 4:3 DVD): preserve width, scale height up.
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
