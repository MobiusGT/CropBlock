import Foundation

public enum BatchEligibilityStatus: Hashable, Sendable {
    case pending
    case scanning
    case detected
    case noBars
    case variableAR
    case cropped
    case error
}

public struct BatchCandidate: Hashable, Sendable {
    public let id: UUID
    public let status: BatchEligibilityStatus
    public let hasNonZeroInsets: Bool
    public let variableARConfirmed: Bool
    public let isApplying: Bool

    public init(
        id: UUID,
        status: BatchEligibilityStatus,
        hasNonZeroInsets: Bool,
        variableARConfirmed: Bool,
        isApplying: Bool = false
    ) {
        self.id = id
        self.status = status
        self.hasNonZeroInsets = hasNonZeroInsets
        self.variableARConfirmed = variableARConfirmed
        self.isApplying = isApplying
    }
}

/// Pure batch selection rules for **Crop All**.
/// Strictly includes only `detected` and explicitly confirmed `variableAR` items with non-zero insets.
/// Automatically skips `noBars`, `error`, `pending`, `scanning`, `cropped`, and unconfirmed `variableAR`.
public enum BatchApplyPlanner {
    public static func eligibleIDs(from candidates: [BatchCandidate]) -> [UUID] {
        candidates.compactMap { candidate in
            guard !candidate.isApplying, candidate.hasNonZeroInsets else { return nil }
            switch candidate.status {
            case .detected:
                return candidate.id
            case .variableAR:
                return candidate.variableARConfirmed ? candidate.id : nil
            case .pending, .scanning, .noBars, .cropped, .error:
                return nil
            }
        }
    }
}

public struct DeepScanCandidate: Hashable, Sendable {
    public let id: UUID
    public let status: BatchEligibilityStatus
    public let isDeepScanned: Bool
    public let isApplying: Bool

    public init(
        id: UUID,
        status: BatchEligibilityStatus,
        isDeepScanned: Bool,
        isApplying: Bool = false
    ) {
        self.id = id
        self.status = status
        self.isDeepScanned = isDeepScanned
        self.isApplying = isApplying
    }
}

/// Pure batch selection rules for **Deep Scan All**.
/// Targets all queued files that have not yet been Deep Scanned and are not already `cropped`,
/// `scanning`, or `applying` (per-file Deep Scan remains available on any row including `cropped`).
public enum DeepScanBatchPlanner {
    public static func eligibleIDs(from candidates: [DeepScanCandidate]) -> [UUID] {
        candidates.compactMap { candidate in
            guard !candidate.isDeepScanned, !candidate.isApplying else { return nil }
            switch candidate.status {
            case .pending, .detected, .noBars, .variableAR, .error:
                return candidate.id
            case .scanning, .cropped:
                return nil
            }
        }
    }
}
