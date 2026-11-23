import Foundation
import Testing
@testable import CropBlockKit

/// Stub H.264/HEVC bitstream crop backend proving Milestone 3 (`h264_metadata` / `hevc_metadata`)
/// plugs into the existing `CropBackend` contract with zero UI or queue refactoring.
private struct StubBitstreamCropBackend: CropBackend {
    let id: CropBackendID = .bitstreamMetadata
    let displayName: String = "H.264/HEVC Bitstream (h264_metadata/hevc_metadata)"

    func canHandle(inspection: VideoInspection) -> Bool {
        let codec = inspection.codecName.lowercased()
        return codec == "h264" || codec == "hevc" || codec == "h265"
    }

    func buildPlan(for inspection: VideoInspection, insets: CropInsets) -> CropApplyPlan {
        let clamped = CropCalculator.clampManualInsets(
            insets,
            frameWidth: inspection.storedWidth,
            frameHeight: inspection.storedHeight
        )
        let display = CropCalculator.displayDimensions(
            storedWidth: inspection.storedWidth,
            storedHeight: inspection.storedHeight,
            insets: clamped,
            sar: inspection.sar
        )
        let bsfName = inspection.codecName.lowercased() == "h264" ? "h264_metadata" : "hevc_metadata"
        let changes = [
            HeaderPropertyChange(
                property: "\(bsfName):crop_left",
                before: "0",
                after: "\(clamped.left)",
                changed: clamped.left > 0
            ),
            HeaderPropertyChange(
                property: "\(bsfName):crop_right",
                before: "0",
                after: "\(clamped.right)",
                changed: clamped.right > 0
            ),
            HeaderPropertyChange(
                property: "\(bsfName):crop_top",
                before: "0",
                after: "\(clamped.top)",
                changed: clamped.top > 0
            ),
            HeaderPropertyChange(
                property: "\(bsfName):crop_bottom",
                before: "0",
                after: "\(clamped.bottom)",
                changed: clamped.bottom > 0
            ),
        ]
        return CropApplyPlan(
            backendID: id,
            storedWidth: inspection.storedWidth,
            storedHeight: inspection.storedHeight,
            insets: clamped,
            displayDimensions: display,
            sar: inspection.sar,
            changes: changes
        )
    }

    func apply(
        plan: CropApplyPlan,
        inspection: VideoInspection,
        to url: URL,
        tools: ResolvedTools,
        existingReceipt: EditReceipt?
    ) async throws -> EditReceipt {
        EditReceipt(
            canonicalPath: MKVFileDiscovery.canonicalPath(for: url),
            fileSize: inspection.fileSize,
            backendID: id,
            originalHeader: existingReceipt?.originalHeader ?? inspection.currentHeader,
            appliedInsets: plan.insets,
            appliedDisplay: plan.displayDimensions,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func restore(
        receipt: EditReceipt?,
        inspection: VideoInspection,
        to url: URL,
        tools: ResolvedTools
    ) async throws {}
}

@Suite("CropBackend protocol extensibility (Milestone 3 hook)")
struct CropBackendProtocolTests {

    @Test("Polymorphic CropBackend supports both MKVHeaderCropBackend and future bitstream backends")
    func polymorphicBackendExtensibility() async throws {
        let h264Inspection = VideoInspection(
            url: URL(fileURLWithPath: "/tmp/movie-h264.mkv"),
            fileSize: 10_000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 6000,
            codecName: "h264",
            currentHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080)
        )
        let vp9Inspection = VideoInspection(
            url: URL(fileURLWithPath: "/tmp/movie-vp9.mkv"),
            fileSize: 10_000,
            storedWidth: 1920,
            storedHeight: 1080,
            sar: .square,
            duration: 6000,
            codecName: "vp9",
            currentHeader: MatroskaVideoHeader(pixelWidth: 1920, pixelHeight: 1080)
        )

        let backends: [any CropBackend] = [
            MKVHeaderCropBackend(),
            StubBitstreamCropBackend(),
        ]
        let insets = CropInsets(left: 0, right: 0, top: 140, bottom: 140)

        // MKV header backend handles any codec; bitstream stub handles only H.264/HEVC
        #expect(backends[0].canHandle(inspection: h264Inspection))
        #expect(backends[0].canHandle(inspection: vp9Inspection))
        #expect(backends[1].canHandle(inspection: h264Inspection))
        #expect(!backends[1].canHandle(inspection: vp9Inspection))

        // Both produce identical geometry plans through the same UI-facing CropApplyPlan struct
        let mkvPlan = backends[0].buildPlan(for: h264Inspection, insets: insets)
        let bsfPlan = backends[1].buildPlan(for: h264Inspection, insets: insets)

        #expect(mkvPlan.backendID == .mkvHeader)
        #expect(bsfPlan.backendID == .bitstreamMetadata)
        #expect(mkvPlan.insets == bsfPlan.insets)
        #expect(mkvPlan.displayDimensions == bsfPlan.displayDimensions)
        #expect(mkvPlan.changes.count == 4)
        #expect(bsfPlan.changes.first?.property == "h264_metadata:crop_left")

        let stubReceipt = try await backends[1].apply(
            plan: bsfPlan,
            inspection: h264Inspection,
            to: h264Inspection.url,
            tools: ResolvedTools(statuses: [:]),
            existingReceipt: nil
        )
        #expect(stubReceipt.backendID == .bitstreamMetadata)
        #expect(stubReceipt.appliedInsets == insets)
    }
}
