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

/// Pure batch selection rules for **Apply All Ready**.
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
