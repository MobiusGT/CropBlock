import Darwin
import Foundation
import Testing
@testable import CropBlockKit

@Suite("MKVHeaderCropBackend commands, errors, receipts, and live round-trip")
struct MKVBackendAndIntegrationTests {

    @Test("Builds exact mkvpropedit apply, receipt restore, and receipt-less reset arguments touching ONLY pixel-crop-*")
    func mkvpropeditArgumentBuilders() {
        let inspection = VideoInspection(
            url: URL(fileURLWithPath: "/tmp/movie.mkv"),
            fileSize: 1000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 6000,
            codecName: "h264",
            currentHeader: MatroskaVideoHeader(
                pixelWidth: 1920,
                pixelHeight: 1080,
                displayWidth: 1920,
                displayHeight: 1080,
                displayUnit: 0
            )
        )
        let backend = MKVHeaderCropBackend()
        let plan = backend.buildPlan(for: inspection, insets: CropInsets(left: 0, right: 0, top: 140, bottom: 140))

        // Plan changes list ONLY the four pixel-crop-* fields
        #expect(plan.changes.map(\.property) == [
            "pixel-crop-left",
            "pixel-crop-right",
            "pixel-crop-top",
            "pixel-crop-bottom",
        ])

        let applyArgs = MKVHeaderCropBackend.buildApplyArguments(filePath: "/tmp/movie.mkv", plan: plan)
        #expect(applyArgs == [
            "/tmp/movie.mkv",
            "--edit", "track:v1",
            "--set", "pixel-crop-left=0",
            "--set", "pixel-crop-right=0",
            "--set", "pixel-crop-top=140",
            "--set", "pixel-crop-bottom=140",
        ])
        #expect(!applyArgs.joined(separator: " ").contains("display-"))

        // Receipt restore: absent pixel-crop-* use --delete, present use --set; display-* never touched
        let restoreHeader = MatroskaVideoHeader(
            pixelWidth: 1920,
            pixelHeight: 1080,
            pixelCropLeft: 0,
            pixelCropRight: nil,
            pixelCropTop: 20,
            pixelCropBottom: nil,
            displayWidth: 1920,
            displayHeight: 1080,
            displayUnit: 0
        )
        let restoreArgs = MKVHeaderCropBackend.buildRestoreArguments(
            filePath: "/tmp/movie.mkv",
            originalHeader: restoreHeader
        )
        #expect(restoreArgs == [
            "/tmp/movie.mkv",
            "--edit", "track:v1",
            "--set", "pixel-crop-left=0",
            "--delete", "pixel-crop-right",
            "--set", "pixel-crop-top=20",
            "--delete", "pixel-crop-bottom",
        ])
        #expect(!restoreArgs.joined(separator: " ").contains("display-"))

        // Receipt-less reset deletes ONLY pixel-crop-* and never touches display-*
        let resetArgs = MKVHeaderCropBackend.buildResetArguments(filePath: "/tmp/movie.mkv")
        #expect(resetArgs == [
            "/tmp/movie.mkv",
            "--edit", "track:v1",
            "--delete", "pixel-crop-left",
            "--delete", "pixel-crop-right",
            "--delete", "pixel-crop-top",
            "--delete", "pixel-crop-bottom",
        ])
        #expect(!resetArgs.joined(separator: " ").contains("display-"))
    }

    @Test("Classifies read-only, permission denied, and SMB/NFS network errors cleanly")
    func gracefulReadOnlyAndNetworkErrorMapping() {
        #expect(
            MKVHeaderCropBackend.mapPosixError(EROFS, fileName: "Movie.mkv")
            == .readOnlyOrPermissionDenied("Movie.mkv")
        )
        #expect(
            MKVHeaderCropBackend.mapPosixError(EACCES, fileName: "Movie.mkv")
            == .readOnlyOrPermissionDenied("Movie.mkv")
        )
        #expect(
            MKVHeaderCropBackend.mapPosixError(ESTALE, fileName: "NAS.mkv")
            == .networkPathUnavailable("NAS.mkv")
        )
        #expect(
            MKVHeaderCropBackend.mapPosixError(EIO, fileName: "NAS.mkv")
            == .networkPathUnavailable("NAS.mkv")
        )
        #expect(
            MKVHeaderCropBackend.classifyToolFailure(
                fileName: "Share.mkv",
                stdout: "",
                stderr: "Error: The file '/Volumes/Media/Share.mkv' could not be opened for reading and writing: Permission denied.",
                exitCode: 2
            ) == .readOnlyOrPermissionDenied("Share.mkv")
        )
        #expect(
            MKVHeaderCropBackend.classifyToolFailure(
                fileName: "Share.mkv",
                stdout: "",
                stderr: "Error: Input/output error while writing '/Volumes/NAS/Share.mkv'",
                exitCode: 2
            ) == .networkPathUnavailable("Share.mkv")
        )
    }

    @Test("ReceiptStore persists and reloads receipts atomically across instances")
    func receiptStorePersistence() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cb-receipts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appending(path: "Film.mkv")
        try Data().write(to: fileURL)

        let receipt = EditReceipt(
            canonicalPath: MKVFileDiscovery.canonicalPath(for: fileURL),
            fileSize: 4096,
            backendID: .mkvHeader,
            originalHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080),
            appliedInsets: CropInsets(left: 0, right: 0, top: 140, bottom: 140),
            appliedDisplay: DisplayDimensions(width: 1920, height: 800),
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let store1 = ReceiptStore(directoryURL: dir)
        try await store1.save(receipt)

        let store2 = ReceiptStore(directoryURL: dir)
        let loaded = await store2.receipt(for: fileURL)
        #expect(loaded == receipt)

        try await store2.remove(for: fileURL)
        let afterRemove = await store2.receipt(for: fileURL)
        #expect(afterRemove == nil)
    }

    @Test("ProcessRunner cancels an active child process promptly when Swift Task cancels")
    func processRunnerCancellation() async {
        let task = Task {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"]
            )
        }
        try? await Task.sleep(for: .milliseconds(100))
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected ProcessRunner to throw on cancellation")
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            #expect(elapsed < 2.0)
        }
    }

    @Test("Live end-to-end scan, apply, re-scan, restore preserves DisplayWidth/Height/Unit untouched")
    func liveRoundTripIntegration() async throws {
        let tools = ToolResolver().resolveAll()
        guard let ffmpeg = tools.ffmpegURL, let mkvpropedit = tools.mkvpropeditURL, tools.allAvailable else {
            return
        }

        let workDir = FileManager.default.temporaryDirectory.appending(path: "cb-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: workDir.appending(path: "sample.mkv").path)
            try? FileManager.default.removeItem(at: workDir)
        }

        let mkvURL = workDir.appending(path: "sample.mkv")
        let previewDir = workDir.appending(path: "previews")

        // 1. Synthesize a 3-second 320x180 H.264 MKV with 30px top & bottom black bars
        let gen = try await ProcessRunner.run(executable: ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=0x3366CC:s=320x120:d=3,pad=320:180:0:30:black",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            mkvURL.path,
        ])
        #expect(gen.terminationStatus == 0)

        // Stamp explicit pre-existing display dimensions to verify Crop Block leaves them completely untouched
        let stamp = try await ProcessRunner.run(executable: mkvpropedit, arguments: [
            mkvURL.path, "--edit", "track:v1",
            "--set", "display-unit=0",
            "--set", "display-width=320",
            "--set", "display-height=180",
        ])
        #expect(stamp.terminationStatus == 0)

        let originalHeader = try MatroskaHeaderReader.readVideoHeader(at: mkvURL)
        #expect(originalHeader.displayWidth == 320)
        #expect(originalHeader.displayHeight == 180)
        #expect(originalHeader.displayUnit == 0)

        // 2. Scan with VideoScanner (Standard + Deep single-pass on short clip)
        let scan1 = try await VideoScanner.scan(
            url: mkvURL,
            settings: DetectionSettings(samplePercentages: [0.25, 0.75], sampleDurationSeconds: 1, cropDetectLimit: 24),
            tools: tools,
            previewCacheDirectory: previewDir
        )
        #expect(scan1.inspection.storedWidth == 320)
        #expect(scan1.inspection.storedHeight == 180)
        #expect(scan1.detection.proposedInsets == CropInsets(left: 0, right: 0, top: 30, bottom: 30))
        #expect(scan1.detection.samples.first?.previewImagePath != nil)

        let deepScan = try await VideoScanner.scan(
            url: mkvURL,
            settings: DetectionSettings.default,
            tools: tools,
            previewCacheDirectory: previewDir,
            mode: .deep
        )
        #expect(deepScan.detection.isDeepScanned)
        #expect(deepScan.detection.isFullVideoSinglePass)
        #expect(deepScan.detection.proposedInsets == CropInsets(left: 0, right: 0, top: 30, bottom: 30))
        #expect(deepScan.detection.deepScanBadgeLabel == "Deep Scanned · Full Video")

        // 3. Apply crop losslessly -> pixel-crop-* set, display-* UNTOUCHED
        let backend = MKVHeaderCropBackend()
        let plan = backend.buildPlan(for: scan1.inspection, insets: scan1.detection.proposedInsets)
        let receipt = try await backend.apply(
            plan: plan,
            inspection: scan1.inspection,
            to: mkvURL,
            tools: tools,
            existingReceipt: nil
        )

        let afterApply = try MatroskaHeaderReader.readVideoHeader(at: mkvURL)
        #expect(afterApply.pixelCropLeft == 0)
        #expect(afterApply.pixelCropRight == 0)
        #expect(afterApply.pixelCropTop == 30)
        #expect(afterApply.pixelCropBottom == 30)
        #expect(afterApply.displayWidth == originalHeader.displayWidth)
        #expect(afterApply.displayHeight == originalHeader.displayHeight)
        #expect(afterApply.displayUnit == originalHeader.displayUnit)

        // 4. Re-scan already-cropped MKV -> `-apply_cropping codec` still sees 320x180 & T=30, B=30
        let scan2 = try await VideoScanner.scan(
            url: mkvURL,
            settings: DetectionSettings(samplePercentages: [0.5], sampleDurationSeconds: 1, cropDetectLimit: 24),
            tools: tools,
            previewCacheDirectory: previewDir
        )
        #expect(scan2.inspection.storedWidth == 320)
        #expect(scan2.inspection.storedHeight == 180)
        #expect(scan2.detection.proposedInsets == CropInsets(left: 0, right: 0, top: 30, bottom: 30))

        // 5. Restore original via receipt -> pixel-crop-* deleted, display-* STILL UNTOUCHED
        try await backend.restore(receipt: receipt, inspection: scan2.inspection, to: mkvURL, tools: tools)
        let afterRestore = try MatroskaHeaderReader.readVideoHeader(at: mkvURL)
        #expect(afterRestore.pixelCropTop == nil)
        #expect(afterRestore.pixelCropBottom == nil)
        #expect(afterRestore.pixelCropLeft == nil)
        #expect(afterRestore.pixelCropRight == nil)
        #expect(afterRestore.displayWidth == originalHeader.displayWidth)
        #expect(afterRestore.displayHeight == originalHeader.displayHeight)
        #expect(afterRestore.displayUnit == originalHeader.displayUnit)

        // 6. Read-only file fails gracefully with .readOnlyOrPermissionDenied
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: mkvURL.path)
        do {
            _ = try await backend.apply(
                plan: plan,
                inspection: scan1.inspection,
                to: mkvURL,
                tools: tools,
                existingReceipt: nil
            )
            Issue.record("Expected readOnlyOrPermissionDenied error on 0444 file")
        } catch let error as MKVEditError {
            #expect(error == .readOnlyOrPermissionDenied("sample.mkv"))
        }
    }
}
