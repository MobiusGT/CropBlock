import Foundation
import CropBlockKit

enum QueueItemStatus: Hashable {
    case pending
    case scanning
    case detected
    case noBars
    case variableAR
    case cropped
    case error(String)

    var label: String {
        switch self {
        case .pending: "Pending"
        case .scanning: "Scanning…"
        case .detected: "Detected"
        case .noBars: "No Bars"
        case .variableAR: "Variable AR"
        case .cropped: "Cropped"
        case .error: "Error"
        }
    }

    var symbol: String {
        switch self {
        case .pending: "clock"
        case .scanning: "hourglass"
        case .detected: "crop"
        case .noBars: "checkmark.circle"
        case .variableAR: "exclamationmark.triangle.fill"
        case .cropped: "checkmark.seal.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}

struct QueueItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let canonicalPath: String
    var parentContext: String?
    var status: QueueItemStatus
    var inspection: VideoInspection?
    var detection: CropDetectionResult?
    var manualInsets: CropInsets?
    var selectedSampleIndex: Int
    var variableARConfirmed: Bool
    var receipt: EditReceipt?
    var isApplying: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        parentContext: String? = nil,
        status: QueueItemStatus = .pending,
        inspection: VideoInspection? = nil,
        detection: CropDetectionResult? = nil,
        manualInsets: CropInsets? = nil,
        selectedSampleIndex: Int = 0,
        variableARConfirmed: Bool = false,
        receipt: EditReceipt? = nil,
        isApplying: Bool = false
    ) {
        self.id = id
        self.url = url
        self.canonicalPath = MKVFileDiscovery.canonicalPath(for: url)
        self.parentContext = parentContext
        self.status = status
        self.inspection = inspection
        self.detection = detection
        self.manualInsets = manualInsets
        self.selectedSampleIndex = selectedSampleIndex
        self.variableARConfirmed = variableARConfirmed
        self.receipt = receipt
        self.isApplying = isApplying
    }

    var fileName: String { url.lastPathComponent }

    var activeInsets: CropInsets {
        if let manualInsets { return manualInsets }
        if let detection { return detection.proposedInsets }
        return .zero
    }

    var isManuallyAdjusted: Bool { manualInsets != nil }

    var canApply: Bool {
        guard !isApplying, let inspection else { return false }
        switch status {
        case .pending, .scanning, .error:
            return false
        case .noBars:
            return !activeInsets.isZero
        case .variableAR:
            return variableARConfirmed && (!activeInsets.isZero || inspection.currentHeader.hasNonZeroCrop)
        case .detected, .cropped:
            return !activeInsets.isZero
        }
    }

    var canRestore: Bool {
        guard !isApplying, let inspection else { return false }
        return receipt != nil || inspection.currentHeader.hasNonZeroCrop
    }

    var restoreButtonTitle: String {
        receipt != nil ? "Restore Original" : "Reset Crop Headers"
    }

    var resolutionSummary: String {
        guard let inspection else { return "Waiting to scan" }
        let stored = inspection.formattedStoredResolution
        let insets = activeInsets
        if !insets.isZero {
            let display = CropCalculator.displayDimensions(
                storedWidth: inspection.storedWidth,
                storedHeight: inspection.storedHeight,
                insets: insets,
                sar: inspection.sar
            )
            return "\(stored) → \(display.formattedDimensions) · \(display.formattedAspectRatio)"
        }
        let full = inspection.fullFrameDisplayDimensions
        return "\(stored) · \(full.formattedAspectRatio)"
    }

    var currentSample: CropSample? {
        guard let samples = detection?.samples, !samples.isEmpty else { return nil }
        let clamped = min(max(0, selectedSampleIndex), samples.count - 1)
        return samples[clamped]
    }
}
