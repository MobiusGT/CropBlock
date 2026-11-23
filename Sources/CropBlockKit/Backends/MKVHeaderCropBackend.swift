import Darwin
import Foundation

public enum MKVEditError: Error, LocalizedError, Equatable, Sendable {
    case missingTool(String)
    case fileNotFound(String)
    case readOnlyOrPermissionDenied(String)
    case networkPathUnavailable(String)
    case fileLockedOrInUse(String)
    case invalidMatroskaFile(String)
    case mkvpropeditFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingTool(let name):
            "Required tool '\(name)' is not installed. Open Tool Setup to install or locate it."
        case .fileNotFound(let name):
            "Unable to find '\(name)'. Check that the file or mounted volume is still available."
        case .readOnlyOrPermissionDenied(let name):
            "Unable to edit '\(name)': file or volume is read-only or locked. Check permissions in Finder."
        case .networkPathUnavailable(let name):
            "Unable to write '\(name)' over the network (SMB/NFS). Reconnect the share and try again."
        case .fileLockedOrInUse(let name):
            "Unable to edit '\(name)': file is currently locked or in use by another app."
        case .invalidMatroskaFile(let name):
            "'\(name)' is not a valid Matroska (.mkv) file."
        case .mkvpropeditFailed(let detail):
            "mkvpropedit could not update the file: \(detail)"
        }
    }
}

/// Lossless in-place Matroska header cropping backend powered by `mkvpropedit --edit track:v1`.
/// Strictly modifies only the four `pixel-crop-*` properties, leaving `display-width`,
/// `display-height`, and `display-unit` completely untouched.
public struct MKVHeaderCropBackend: CropBackend, Sendable {
    public let id: CropBackendID = .mkvHeader
    public let displayName: String = "Matroska Header (mkvpropedit)"

    public init() {}

    public func canHandle(inspection: VideoInspection) -> Bool {
        inspection.storedWidth > 0 && inspection.storedHeight > 0
    }

    public func buildPlan(for inspection: VideoInspection, insets: CropInsets) -> CropApplyPlan {
        let clamped = CropCalculator.clampManualInsets(
            insets,
            frameWidth: inspection.storedWidth,
            frameHeight: inspection.storedHeight
        )
        // Computed purely for preview/aspect-ratio display in the UI; never written to the MKV header.
        let effectiveDisplay = CropCalculator.displayDimensions(
            storedWidth: inspection.storedWidth,
            storedHeight: inspection.storedHeight,
            insets: clamped,
            sar: inspection.sar
        )
        let current = inspection.currentHeader

        func fmtOptional(_ value: Int?, fallback: String = "0 (unset)") -> String {
            value.map(String.init) ?? fallback
        }

        let changes: [HeaderPropertyChange] = [
            HeaderPropertyChange(
                property: "pixel-crop-left",
                before: fmtOptional(current.pixelCropLeft),
                after: "\(clamped.left)",
                changed: (current.pixelCropLeft ?? 0) != clamped.left || current.pixelCropLeft == nil
            ),
            HeaderPropertyChange(
                property: "pixel-crop-right",
                before: fmtOptional(current.pixelCropRight),
                after: "\(clamped.right)",
                changed: (current.pixelCropRight ?? 0) != clamped.right || current.pixelCropRight == nil
            ),
            HeaderPropertyChange(
                property: "pixel-crop-top",
                before: fmtOptional(current.pixelCropTop),
                after: "\(clamped.top)",
                changed: (current.pixelCropTop ?? 0) != clamped.top || current.pixelCropTop == nil
            ),
            HeaderPropertyChange(
                property: "pixel-crop-bottom",
                before: fmtOptional(current.pixelCropBottom),
                after: "\(clamped.bottom)",
                changed: (current.pixelCropBottom ?? 0) != clamped.bottom || current.pixelCropBottom == nil
            ),
        ]

        return CropApplyPlan(
            backendID: id,
            storedWidth: inspection.storedWidth,
            storedHeight: inspection.storedHeight,
            insets: clamped,
            displayDimensions: effectiveDisplay,
            sar: inspection.sar,
            changes: changes
        )
    }

    /// Pure argument builder for `mkvpropedit` apply — touches ONLY `pixel-crop-*`.
    public static func buildApplyArguments(filePath: String, plan: CropApplyPlan) -> [String] {
        [
            filePath,
            "--edit", "track:v1",
            "--set", "pixel-crop-left=\(plan.insets.left)",
            "--set", "pixel-crop-right=\(plan.insets.right)",
            "--set", "pixel-crop-top=\(plan.insets.top)",
            "--set", "pixel-crop-bottom=\(plan.insets.bottom)",
        ]
    }

    /// Pure argument builder for exact restoration from a saved `EditReceipt` — touches ONLY `pixel-crop-*`.
    public static func buildRestoreArguments(filePath: String, originalHeader: MatroskaVideoHeader) -> [String] {
        var args = [filePath, "--edit", "track:v1"]

        func restoreField(_ name: String, value: Int?) {
            if let value {
                args += ["--set", "\(name)=\(value)"]
            } else {
                args += ["--delete", name]
            }
        }

        restoreField("pixel-crop-left", value: originalHeader.pixelCropLeft)
        restoreField("pixel-crop-right", value: originalHeader.pixelCropRight)
        restoreField("pixel-crop-top", value: originalHeader.pixelCropTop)
        restoreField("pixel-crop-bottom", value: originalHeader.pixelCropBottom)
        return args
    }

    /// Pure argument builder for receipt-less reset — deletes ONLY `pixel-crop-*`.
    public static func buildResetArguments(filePath: String) -> [String] {
        [
            filePath,
            "--edit", "track:v1",
            "--delete", "pixel-crop-left",
            "--delete", "pixel-crop-right",
            "--delete", "pixel-crop-top",
            "--delete", "pixel-crop-bottom",
        ]
    }

    public func apply(
        plan: CropApplyPlan,
        inspection: VideoInspection,
        to url: URL,
        tools: ResolvedTools,
        existingReceipt: EditReceipt?
    ) async throws -> EditReceipt {
        guard let mkvpropedit = tools.mkvpropeditURL else {
            throw MKVEditError.missingTool("mkvpropedit")
        }
        try Self.preflightWriteAccess(to: url)

        // Preserve the true original pre-Crop-Block pixel-crop headers if the file was edited before.
        let originalHeader = existingReceipt?.originalHeader ?? inspection.currentHeader
        let args = Self.buildApplyArguments(filePath: url.path, plan: plan)
        let output = try await ProcessRunner.run(executable: mkvpropedit, arguments: args)
        if output.terminationStatus != 0 {
            throw Self.classifyToolFailure(
                fileName: url.lastPathComponent,
                stdout: output.stdoutString,
                stderr: output.stderrString,
                exitCode: output.terminationStatus
            )
        }

        let canonical = MKVFileDiscovery.canonicalPath(for: url)
        return EditReceipt(
            canonicalPath: canonical,
            fileSize: inspection.fileSize,
            backendID: id,
            originalHeader: originalHeader,
            appliedInsets: plan.insets,
            appliedDisplay: plan.displayDimensions,
            appliedAt: Date()
        )
    }

    public func restore(
        receipt: EditReceipt?,
        inspection: VideoInspection,
        to url: URL,
        tools: ResolvedTools
    ) async throws {
        guard let mkvpropedit = tools.mkvpropeditURL else {
            throw MKVEditError.missingTool("mkvpropedit")
        }
        try Self.preflightWriteAccess(to: url)

        let args: [String]
        if let receipt {
            args = Self.buildRestoreArguments(filePath: url.path, originalHeader: receipt.originalHeader)
        } else {
            args = Self.buildResetArguments(filePath: url.path)
        }

        let output = try await ProcessRunner.run(executable: mkvpropedit, arguments: args)
        if output.terminationStatus != 0 {
            throw Self.classifyToolFailure(
                fileName: url.lastPathComponent,
                stdout: output.stdoutString,
                stderr: output.stderrString,
                exitCode: output.terminationStatus
            )
        }
    }

    /// Validates existence, EBML header, and real POSIX write permission (covering local chmod,
    /// read-only volumes, Finder immutable lock, and SMB/NFS network disconnects) without modifying bytes.
    public static func preflightWriteAccess(to url: URL) throws {
        let name = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MKVEditError.fileNotFound(name)
        }

        let fd = Darwin.open(url.path, O_RDWR)
        if fd < 0 {
            let code = errno
            throw mapPosixError(code, fileName: name)
        }
        Darwin.close(fd)

        guard MatroskaHeaderReader.hasEBMLMagic(at: url) else {
            throw MKVEditError.invalidMatroskaFile(name)
        }
    }

    public static func mapPosixError(_ code: Int32, fileName: String) -> MKVEditError {
        switch code {
        case ENOENT, ENOTDIR:
            return .fileNotFound(fileName)
        case EACCES, EPERM, EROFS:
            return .readOnlyOrPermissionDenied(fileName)
        case EIO, ENOTCONN, ESTALE, EHOSTDOWN, EHOSTUNREACH, ETIMEDOUT, ENETDOWN, ENETUNREACH:
            return .networkPathUnavailable(fileName)
        case EBUSY, ETXTBSY:
            return .fileLockedOrInUse(fileName)
        default:
            let message = String(cString: strerror(code))
            return .mkvpropeditFailed(message)
        }
    }

    /// Maps `mkvpropedit` stdout/stderr messages into actionable per-file errors (including SMB/NFS drops).
    public static func classifyToolFailure(
        fileName: String,
        stdout: String,
        stderr: String,
        exitCode: Int32
    ) -> MKVEditError {
        let combined = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let lower = combined.lowercased()

        if lower.contains("permission denied")
            || lower.contains("read-only file system")
            || lower.contains("read-only")
            || lower.contains("operation not permitted")
            || lower.contains("could not be opened for reading and writing") {
            return .readOnlyOrPermissionDenied(fileName)
        }
        if lower.contains("input/output error")
            || lower.contains("stale nfs")
            || lower.contains("host is down")
            || lower.contains("network")
            || lower.contains("socket is not connected")
            || lower.contains("connection timed out") {
            return .networkPathUnavailable(fileName)
        }
        if lower.contains("resource busy") || lower.contains("text file busy") {
            return .fileLockedOrInUse(fileName)
        }
        if lower.contains("no such file") || lower.contains("could not be opened for reading") {
            return .fileNotFound(fileName)
        }
        if lower.contains("not a matroska file") || lower.contains("invalid ebml") {
            return .invalidMatroskaFile(fileName)
        }

        let summaryLine = combined
            .split(whereSeparator: \.isNewline)
            .first { $0.localizedCaseInsensitiveContains("error") }
            .map(String.init)
            ?? combined.split(whereSeparator: \.isNewline).last.map(String.init)
            ?? "exit code \(exitCode)"
        return .mkvpropeditFailed(summaryLine)
    }
}
