import AppKit
import CoreGraphics
import Foundation
import CropBlockKit

/// Populates deterministic queue items + synthetic cinema preview images when `APP_SEED=1`
/// so light and dark snapshots exercise every status badge, crop overlay, Variable AR warning, and sheet.
enum SeedData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["APP_SEED"] == "1"
    }

    static func populate(into model: AppModel) {
        let previewDir = URL(fileURLWithPath: "/tmp/CropBlock-seed-previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        let dune20 = renderCinemaFrame(
            to: previewDir.appending(path: "dune-20.png"),
            width: 960, height: 540, barHeight: 68,
            topColor: (0.85, 0.56, 0.28), bottomColor: (0.28, 0.16, 0.08),
            accentColor: (0.98, 0.78, 0.45), sceneLabel: "20% · Arrakis Desert"
        )
        let dune50 = renderCinemaFrame(
            to: previewDir.appending(path: "dune-50.png"),
            width: 960, height: 540, barHeight: 68,
            topColor: (0.16, 0.27, 0.46), bottomColor: (0.07, 0.10, 0.18),
            accentColor: (0.45, 0.72, 0.96), sceneLabel: "50% · Ornithopter Flight"
        )
        let dune80 = renderCinemaFrame(
            to: previewDir.appending(path: "dune-80.png"),
            width: 960, height: 540, barHeight: 68,
            topColor: (0.64, 0.30, 0.18), bottomColor: (0.14, 0.07, 0.06),
            accentColor: (0.95, 0.54, 0.30), sceneLabel: "80% · Sunset Horizon"
        )

        let imax20 = renderCinemaFrame(
            to: previewDir.appending(path: "imax-20.png"),
            width: 960, height: 540, barHeight: 68,
            topColor: (0.20, 0.32, 0.42), bottomColor: (0.10, 0.14, 0.19),
            accentColor: (0.68, 0.80, 0.88), sceneLabel: "20% · 2.39:1 Scope"
        )
        let imax50 = renderCinemaFrame(
            to: previewDir.appending(path: "imax-50.png"),
            width: 960, height: 540, barHeight: 0,
            topColor: (0.08, 0.12, 0.22), bottomColor: (0.02, 0.04, 0.09),
            accentColor: (0.98, 0.76, 0.38), sceneLabel: "50% · 1.78:1 IMAX Full Frame"
        )

        let arrival50 = renderCinemaFrame(
            to: previewDir.appending(path: "arrival-50.png"),
            width: 960, height: 540, barHeight: 68,
            topColor: (0.44, 0.50, 0.54), bottomColor: (0.17, 0.22, 0.24),
            accentColor: (0.82, 0.86, 0.88), sceneLabel: "50% · Misty Valley"
        )

        // 1. Detected (4K 2.39:1 Letterbox)
        let duneURL = URL(fileURLWithPath: "/Movies/Sci-Fi/Dune.Part.Two.2024.2160p.Remux.mkv")
        let duneInspection = VideoInspection(
            url: duneURL,
            fileSize: 68_420_000_000,
            storedWidth: 3840,
            storedHeight: 2160,
            sar: .square,
            duration: 9960,
            codecName: "hevc",
            currentHeader: MatroskaVideoHeader(pixelWidth: 3840, pixelHeight: 2160, displayWidth: 3840, displayHeight: 2160)
        )
        let duneSamples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.20, startTime: 1987, duration: 10),
                       detectedRect: CropRect(x: 0, y: 276, width: 3840, height: 1608), previewImagePath: dune20),
            CropSample(window: SampleWindow(index: 1, percentage: 0.50, startTime: 4975, duration: 10),
                       detectedRect: CropRect(x: 0, y: 276, width: 3840, height: 1608), previewImagePath: dune50),
            CropSample(window: SampleWindow(index: 2, percentage: 0.80, startTime: 7963, duration: 10),
                       detectedRect: CropRect(x: 0, y: 276, width: 3840, height: 1608), previewImagePath: dune80),
        ]
        let duneDetection = CropCalculator.unionAndAnalyze(samples: duneSamples, frameWidth: 3840, frameHeight: 2160)
        let duneItem = QueueItem(
            url: duneURL,
            status: .detected,
            inspection: duneInspection,
            detection: duneDetection,
            selectedSampleIndex: 1
        )

        // 2. Film Transfer Jitter (8px edge drift -> suggests Deep Scan without Variable AR block)
        let filmURL = URL(fileURLWithPath: "/Movies/Classics/Blade.Runner.1982.35mm.1080p.mkv")
        let filmInspection = VideoInspection(
            url: filmURL,
            fileSize: 31_400_000_000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 7020, // 117 min -> 17 Deep Scan intervals
            codecName: "h264",
            currentHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080, displayWidth: 1920, displayHeight: 1080)
        )
        let filmSamples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.20, startTime: 1399, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: dune20),
            CropSample(window: SampleWindow(index: 1, percentage: 0.50, startTime: 3505, duration: 10),
                       detectedRect: CropRect(x: 0, y: 144, width: 1920, height: 792), previewImagePath: dune50),
            CropSample(window: SampleWindow(index: 2, percentage: 0.80, startTime: 5611, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: dune80),
        ]
        let filmDetection = CropCalculator.unionAndAnalyze(
            samples: filmSamples,
            frameWidth: 1920,
            frameHeight: 1080,
            scanMode: .standard
        )
        let filmItem = QueueItem(
            url: filmURL,
            status: .detected,
            inspection: filmInspection,
            detection: filmDetection,
            selectedSampleIndex: 1
        )

        // 3. Deep Scanned (90 min -> 15 Deep Scan intervals, 5 representative previews)
        let deepURL = URL(fileURLWithPath: "/Movies/Classics/Lawrence.1962.Restored.2160p.mkv")
        let deepInspection = VideoInspection(
            url: deepURL,
            fileSize: 54_200_000_000,
            storedWidth: 3840,
            storedHeight: 2160,
            sar: .square,
            duration: 5400, // 90 min -> 15 intervals
            codecName: "hevc",
            currentHeader: MatroskaVideoHeader(pixelWidth: 3840, pixelHeight: 2160, displayWidth: 3840, displayHeight: 2160)
        )
        let (deepWindows, _) = CropCalculator.deepScanWindows(duration: 5400, settings: .default)
        let previewPaths = [dune20, dune50, dune80, arrival50, dune20]
        var deepSamples = deepWindows.map { win in
            CropSample(window: win, detectedRect: CropRect(x: 0, y: 216, width: 3840, height: 1728))
        }
        let previewIdx = CropCalculator.selectPreviewIndices(samples: deepSamples, maxCount: 5)
        for (slot, sampleIndex) in previewIdx.enumerated() {
            deepSamples[sampleIndex].previewImagePath = previewPaths[slot % previewPaths.count]
        }
        let deepDetection = CropCalculator.unionAndAnalyze(
            samples: deepSamples,
            frameWidth: 3840,
            frameHeight: 2160,
            scanMode: .deep
        )
        let deepItem = QueueItem(
            url: deepURL,
            status: .detected,
            inspection: deepInspection,
            detection: deepDetection,
            selectedSampleIndex: 2
        )

        // 4. Variable AR (IMAX 1.90:1 / 1.78:1 mixed with 2.39:1)
        let imaxURL = URL(fileURLWithPath: "/Movies/Sci-Fi/Interstellar.2014.IMAX.1080p.mkv")
        let imaxInspection = VideoInspection(
            url: imaxURL,
            fileSize: 34_180_000_000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 10140,
            codecName: "h264",
            currentHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080, displayWidth: 1920, displayHeight: 1080)
        )
        let imaxSamples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.20, startTime: 2023, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: imax20),
            CropSample(window: SampleWindow(index: 1, percentage: 0.50, startTime: 5065, duration: 10),
                       detectedRect: CropRect(x: 0, y: 34, width: 1920, height: 1012), previewImagePath: imax50),
            CropSample(window: SampleWindow(index: 2, percentage: 0.80, startTime: 8107, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: imax20),
        ]
        let imaxDetection = CropCalculator.unionAndAnalyze(samples: imaxSamples, frameWidth: 1920, frameHeight: 1080)
        let imaxItem = QueueItem(
            url: imaxURL,
            status: .variableAR,
            inspection: imaxInspection,
            detection: imaxDetection,
            selectedSampleIndex: 1
        )

        // 3. Cropped (with persisted Receipt for 1-click Restore Original)
        let arrivalURL = URL(fileURLWithPath: "/Movies/Sci-Fi/Arrival.2016.1080p.mkv")
        let arrivalInspection = VideoInspection(
            url: arrivalURL,
            fileSize: 28_900_000_000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 6960,
            codecName: "h264",
            currentHeader: MatroskaVideoHeader(
                pixelWidth: 1920, pixelHeight: 1080,
                pixelCropLeft: 0, pixelCropRight: 0, pixelCropTop: 140, pixelCropBottom: 140,
                displayWidth: 1920, displayHeight: 1080
            )
        )
        let arrivalSamples = [
            CropSample(window: SampleWindow(index: 0, percentage: 0.20, startTime: 1387, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: arrival50),
            CropSample(window: SampleWindow(index: 1, percentage: 0.50, startTime: 3475, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: arrival50),
            CropSample(window: SampleWindow(index: 2, percentage: 0.80, startTime: 5563, duration: 10),
                       detectedRect: CropRect(x: 0, y: 140, width: 1920, height: 800), previewImagePath: arrival50),
        ]
        let arrivalDetection = CropCalculator.unionAndAnalyze(samples: arrivalSamples, frameWidth: 1920, frameHeight: 1080)
        let arrivalReceipt = EditReceipt(
            canonicalPath: arrivalURL.path,
            fileSize: 28_900_000_000,
            backendID: .mkvHeader,
            originalHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080, displayWidth: 1920, displayHeight: 1080),
            appliedInsets: CropInsets(left: 0, right: 0, top: 140, bottom: 140),
            appliedDisplay: DisplayDimensions(width: 1920, height: 800)
        )
        let arrivalItem = QueueItem(
            url: arrivalURL,
            status: .cropped,
            inspection: arrivalInspection,
            detection: arrivalDetection,
            selectedSampleIndex: 1,
            receipt: arrivalReceipt
        )

        // 4 & 5. Duplicate filename disambiguation (Season 1 = No Bars, Season 2 = Pending)
        let epS1URL = URL(fileURLWithPath: "/TV/Severance/Season 1/Episode 01.mkv")
        let epS1Inspection = VideoInspection(
            url: epS1URL,
            fileSize: 4_200_000_000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 3420,
            codecName: "hevc",
            currentHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080)
        )
        let epS1Detection = CropCalculator.unionAndAnalyze(
            samples: [
                CropSample(window: SampleWindow(index: 0, percentage: 0.50, startTime: 1705, duration: 10),
                           detectedRect: CropRect(x: 0, y: 0, width: 1920, height: 1080), previewImagePath: imax50),
            ],
            frameWidth: 1920,
            frameHeight: 1080
        )
        let epS1Item = QueueItem(
            url: epS1URL,
            parentContext: "Season 1",
            status: .noBars,
            inspection: epS1Inspection,
            detection: epS1Detection
        )

        let epS2URL = URL(fileURLWithPath: "/TV/Severance/Season 2/Episode 01.mkv")
        let epS2Item = QueueItem(
            url: epS2URL,
            parentContext: "Season 2",
            status: .pending
        )

        // 6. Error (Read-only / SMB share)
        let nasURL = URL(fileURLWithPath: "/Volumes/MediaNAS/Classic.DVD.NTSC.mkv")
        let nasItem = QueueItem(
            url: nasURL,
            status: .error(MKVEditError.readOnlyOrPermissionDenied("Classic.DVD.NTSC.mkv").localizedDescription)
        )

        model.items = [duneItem, filmItem, deepItem, imaxItem, arrivalItem, epS1Item, epS2Item, nasItem]
        model.selectionID = duneItem.id
    }

    static func mockPartiallyMissingTools() -> ResolvedTools {
        ResolvedTools(statuses: [
            .ffmpeg: .found(url: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), source: .homebrew, version: "9.0.1"),
            .ffprobe: .found(url: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"), source: .homebrew, version: "9.0.1"),
            .mkvpropedit: .missing(reason: "mkvpropedit not found in bundled helpers, Homebrew, or PATH."),
        ])
    }

    private static func renderCinemaFrame(
        to url: URL,
        width: Int,
        height: Int,
        barHeight: Int,
        topColor: (CGFloat, CGFloat, CGFloat),
        bottomColor: (CGFloat, CGFloat, CGFloat),
        accentColor: (CGFloat, CGFloat, CGFloat),
        sceneLabel: String
    ) -> String {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return url.path
        }

        // Fill black background (letterbox bars)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Active picture rect
        let activeRect = CGRect(x: 0, y: barHeight, width: width, height: height - barHeight * 2)
        ctx.saveGState()
        ctx.clip(to: activeRect)

        // Atmospheric sky-to-ground gradient
        let colors = [
            CGColor(srgbRed: bottomColor.0, green: bottomColor.1, blue: bottomColor.2, alpha: 1),
            CGColor(srgbRed: topColor.0, green: topColor.1, blue: topColor.2, alpha: 1),
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: activeRect.minY),
                end: CGPoint(x: 0, y: activeRect.maxY),
                options: []
            )
        }

        // Subtle cinematic horizon glow & silhouette hills
        let glowColors = [
            CGColor(srgbRed: accentColor.0, green: accentColor.1, blue: accentColor.2, alpha: 0.75),
            CGColor(srgbRed: accentColor.0, green: accentColor.1, blue: accentColor.2, alpha: 0.0),
        ] as CFArray
        if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) {
            let center = CGPoint(x: CGFloat(width) * 0.62, y: activeRect.minY + activeRect.height * 0.56)
            ctx.drawRadialGradient(radial, startCenter: center, startRadius: 0, endCenter: center, endRadius: 210, options: [])
        }

        // Foreground ridge silhouette
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: activeRect.minY))
        ctx.addLine(to: CGPoint(x: 0, y: activeRect.minY + activeRect.height * 0.34))
        ctx.addCurve(
            to: CGPoint(x: CGFloat(width) * 0.52, y: activeRect.minY + activeRect.height * 0.24),
            control1: CGPoint(x: CGFloat(width) * 0.18, y: activeRect.minY + activeRect.height * 0.44),
            control2: CGPoint(x: CGFloat(width) * 0.36, y: activeRect.minY + activeRect.height * 0.16)
        )
        ctx.addCurve(
            to: CGPoint(x: CGFloat(width), y: activeRect.minY + activeRect.height * 0.30),
            control1: CGPoint(x: CGFloat(width) * 0.72, y: activeRect.minY + activeRect.height * 0.36),
            control2: CGPoint(x: CGFloat(width) * 0.88, y: activeRect.minY + activeRect.height * 0.20)
        )
        ctx.addLine(to: CGPoint(x: CGFloat(width), y: activeRect.minY))
        ctx.closePath()
        ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.05, blue: 0.07, alpha: 0.88))
        ctx.fillPath()
        ctx.restoreGState()

        if let cgImage = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
        return url.path
    }
}
