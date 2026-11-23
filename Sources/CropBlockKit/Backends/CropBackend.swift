import Foundation

/// Protocol abstracting lossless cropping execution so alternative backends
/// (e.g., H.264/HEVC bitstream SPS cropping via `h264_metadata`/`hevc_metadata`)
/// can be plugged in without refactoring queue or preview UI.
public protocol CropBackend: Sendable {
    var id: CropBackendID { get }
    var displayName: String { get }

    /// Returns `true` when this backend can losslessly crop the inspected stream.
    func canHandle(inspection: VideoInspection) -> Bool

    /// Computes the exact header/metadata changes that applying `insets` will make.
    func buildPlan(for inspection: VideoInspection, insets: CropInsets) -> CropApplyPlan

    /// Applies `plan` in-place to `url` and returns a receipt capturing original state for Restore.
    func apply(
        plan: CropApplyPlan,
        inspection: VideoInspection,
        to url: URL,
        tools: ResolvedTools,
        existingReceipt: EditReceipt?
    ) async throws -> EditReceipt

    /// Reverses a previous edit using `receipt` if present, or resets crop metadata when `receipt` is `nil`.
    func restore(
        receipt: EditReceipt?,
        inspection: VideoInspection,
        to url: URL,
        tools: ResolvedTools
    ) async throws
}
