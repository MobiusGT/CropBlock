import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import CropBlockKit

@Observable
final class AppModel {
    static let shared = AppModel()

    var items: [QueueItem] = [] { didSet { syncMenu() } }
    var selectionID: UUID? { didSet { syncMenu() } }
    var settingsTab: SettingsTab = .general

    var tools: ResolvedTools
    var customToolPaths: CustomToolPaths
    var detectionSettings: DetectionSettings {
        didSet { persistDetectionSettings() }
    }
    var savedReceiptCount = 0

    var showsToolSetupSheet = false
    var showsCompatibilityPopover = false
    var showsCropOverlay = true { didSet { syncMenu() } }
    var isDropTargeted = false
    var banner: AppBanner?

    var isScanning = false { didSet { syncMenu() } }
    var activeBatchScanMode: ScanMode = .standard
    var activeScanCount = 0
    var batchScanCompleted = 0
    var batchScanTotal = 0
    var isBatchApplying = false { didSet { syncMenu() } }
    var batchApplyCompleted = 0
    var batchApplyTotal = 0

    @ObservationIgnored let backend: any CropBackend = MKVHeaderCropBackend()
    @ObservationIgnored let receiptStore: ReceiptStore
    @ObservationIgnored let previewCacheDir: URL
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var batchApplyTask: Task<Void, Never>?
    @ObservationIgnored private var bannerDismissTask: Task<Void, Never>?
    @ObservationIgnored private var hasCheckedInitialTools = false

    private enum DefaultsKey {
        static let customFFmpeg = "tools.custom.ffmpeg"
        static let customFFprobe = "tools.custom.ffprobe"
        static let customMkvpropedit = "tools.custom.mkvpropedit"
        static let detectionSettings = "detection.settings.v1"
    }

    init(storeDirectory: URL = StoreLocation.directoryURL) {
        self.receiptStore = ReceiptStore(directoryURL: storeDirectory)
        self.previewCacheDir = FileManager.default.temporaryDirectory
            .appending(path: "CropBlock-Previews-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        let savedPaths = CustomToolPaths(
            ffmpeg: UserDefaults.standard.string(forKey: DefaultsKey.customFFmpeg) ?? "",
            ffprobe: UserDefaults.standard.string(forKey: DefaultsKey.customFFprobe) ?? "",
            mkvpropedit: UserDefaults.standard.string(forKey: DefaultsKey.customMkvpropedit) ?? ""
        )
        self.customToolPaths = savedPaths
        self.detectionSettings = DetectionSettings.decode(
            from: UserDefaults.standard.data(forKey: DefaultsKey.detectionSettings)
        )
        self.tools = ToolResolver().resolveAll(customPaths: savedPaths)
        syncMenu()
    }

    var selectedItem: QueueItem? {
        guard let selectionID else { return nil }
        return items.first { $0.id == selectionID }
    }

    var queueSubtitle: String {
        items.count == 1 ? "1 file" : "\(items.count) files"
    }

    var cropAllReadyIDs: [UUID] {
        let candidates = items.map { item -> BatchCandidate in
            BatchCandidate(
                id: item.id,
                status: eligibilityStatus(for: item.status),
                hasNonZeroInsets: !item.activeInsets.isZero,
                variableARConfirmed: item.variableARConfirmed,
                isApplying: item.isApplying
            )
        }
        return BatchApplyPlanner.eligibleIDs(from: candidates)
    }

    var cropAllReadyCount: Int { cropAllReadyIDs.count }

    var deepScanEligibleIDs: [UUID] {
        let candidates = items.map { item in
            DeepScanCandidate(
                id: item.id,
                status: eligibilityStatus(for: item.status),
                isDeepScanned: item.isDeepScanned,
                isApplying: item.isApplying
            )
        }
        return DeepScanBatchPlanner.eligibleIDs(from: candidates)
    }

    var deepScanAllCount: Int { deepScanEligibleIDs.count }

    private func eligibilityStatus(for status: QueueItemStatus) -> BatchEligibilityStatus {
        switch status {
        case .pending: .pending
        case .scanning: .scanning
        case .detected: .detected
        case .noBars: .noBars
        case .variableAR: .variableAR
        case .cropped: .cropped
        case .error: .error
        }
    }

    func plan(for item: QueueItem) -> CropApplyPlan? {
        guard let inspection = item.inspection else { return nil }
        return backend.buildPlan(for: inspection, insets: item.activeInsets)
    }

    // MARK: - Tool Discovery

    func startupCheck() async {
        guard !hasCheckedInitialTools else { return }
        hasCheckedInitialTools = true
        await refreshReceiptCount()
        await refreshTools(presentSheetIfMissing: !Snapshot.isActive && !SelfTest.requested)
    }

    func refreshReceiptCount() async {
        savedReceiptCount = await receiptStore.allReceipts().count
    }

    func clearAllReceipts() {
        Task {
            try? await receiptStore.removeAll()
            for idx in items.indices {
                items[idx].receipt = nil
            }
            savedReceiptCount = 0
            syncMenu()
        }
    }

    func resetDetectionSettings() {
        detectionSettings = .default
    }

    func updateSamplePercentage(at index: Int, percent: Int) {
        var next = detectionSettings.samplePercentages
        while next.count <= index {
            next.append(0.50)
        }
        next[index] = min(0.99, max(0.01, Double(percent) / 100.0))
        detectionSettings = DetectionSettings(
            samplePercentages: next,
            sampleDurationSeconds: detectionSettings.sampleDurationSeconds,
            cropDetectLimit: detectionSettings.cropDetectLimit,
            noiseFloorPixels: detectionSettings.noiseFloorPixels,
            maxConcurrentScans: detectionSettings.maxConcurrentScans,
            autoScanOnAdd: detectionSettings.autoScanOnAdd
        )
    }

    private func persistDetectionSettings() {
        guard !Snapshot.isActive, !SelfTest.requested else { return }
        if let data = detectionSettings.encode() {
            UserDefaults.standard.set(data, forKey: DefaultsKey.detectionSettings)
        }
    }

    func refreshTools(presentSheetIfMissing: Bool = false) async {
        let resolved = await ToolResolver().resolveAllWithVersions(customPaths: customToolPaths)
        tools = resolved
        if presentSheetIfMissing && !resolved.allAvailable {
            showsToolSetupSheet = true
        }
    }

    func setCustomToolPath(_ path: String, for tool: ExternalTool) {
        customToolPaths[tool] = path
        switch tool {
        case .ffmpeg: UserDefaults.standard.set(path, forKey: DefaultsKey.customFFmpeg)
        case .ffprobe: UserDefaults.standard.set(path, forKey: DefaultsKey.customFFprobe)
        case .mkvpropedit: UserDefaults.standard.set(path, forKey: DefaultsKey.customMkvpropedit)
        }
        Task { await refreshTools(presentSheetIfMissing: false) }
    }

    func browseCustomTool(for tool: ExternalTool) {
        let panel = NSOpenPanel()
        panel.title = "Locate \(tool.displayName)"
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let existing = tools[tool].url {
            panel.directoryURL = existing.deletingLastPathComponent()
        } else if FileManager.default.fileExists(atPath: "/opt/homebrew/bin") {
            panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        }
        if panel.runModal() == .OK, let url = panel.url {
            setCustomToolPath(url.path, for: tool)
        }
    }

    // MARK: - Queue Intake & Management

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Add MKV Files or Folders"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        var types: [UTType] = [.folder]
        if let mkv = UTType(filenameExtension: "mkv") {
            types.insert(mkv, at: 0)
        }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    func addURLs(_ urls: [URL], autoScan: Bool? = nil) {
        guard !urls.isEmpty else { return }
        let existing = Set(items.map(\.canonicalPath))
        let discovery = MKVFileDiscovery.discoverMKVFiles(from: urls, existingCanonicalPaths: existing)

        if discovery.urls.isEmpty {
            if discovery.skippedNonMKVCount > 0 {
                showBanner("No MKV files found in the dropped items.", kind: .info)
            }
            return
        }

        dismissBanner()
        var newlyAddedIDs: [UUID] = []
        for url in discovery.urls {
            let item = QueueItem(url: url)
            items.append(item)
            newlyAddedIDs.append(item.id)
        }

        recomputeParentContextLabels()
        if selectionID == nil {
            selectionID = newlyAddedIDs.first
        }

        let addedSnapshot = items.filter { newlyAddedIDs.contains($0.id) }
        Task {
            for item in addedSnapshot {
                if let receipt = await receiptStore.receipt(for: item.url) {
                    updateItem(id: item.id) { $0.receipt = receipt }
                }
            }
            let shouldScan = autoScan ?? detectionSettings.autoScanOnAdd
            if shouldScan {
                if tools.allAvailable {
                    scanAllPending()
                } else if !Snapshot.isActive && !SelfTest.requested {
                    showsToolSetupSheet = true
                }
            }
        }
    }

    func removeItem(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectionID == id
        items.remove(at: idx)
        recomputeParentContextLabels()
        if wasSelected {
            if items.isEmpty {
                selectionID = nil
            } else {
                selectionID = items[min(idx, items.count - 1)].id
            }
        }
    }

    func removeSelected() {
        guard let selectionID else { return }
        removeItem(id: selectionID)
    }

    func clearCompleted() {
        let removedSelection = selectedItem.map { $0.status == .cropped || $0.status == .noBars } ?? false
        items.removeAll { $0.status == .cropped || $0.status == .noBars }
        recomputeParentContextLabels()
        if removedSelection {
            selectionID = items.first?.id
        }
    }

    func revealInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func selectSample(_ index: Int, for id: UUID) {
        updateItem(id: id) { item in
            let count = item.previewSamples.count
            guard count > 0 else { return }
            item.selectedSampleIndex = min(max(0, index), count - 1)
        }
    }

    func setVariableARConfirmed(_ confirmed: Bool, for id: UUID) {
        updateItem(id: id) { $0.variableARConfirmed = confirmed }
    }

    func setInset(_ edge: CropEdge, value: Int, for id: UUID) {
        updateItem(id: id) { item in
            guard let inspection = item.inspection else { return }
            var next = item.activeInsets
            switch edge {
            case .top: next.top = value
            case .bottom: next.bottom = value
            case .left: next.left = value
            case .right: next.right = value
            }
            let clamped = CropCalculator.clampManualInsets(
                next,
                frameWidth: inspection.storedWidth,
                frameHeight: inspection.storedHeight
            )
            if let detected = item.detection?.proposedInsets, clamped == detected {
                item.manualInsets = nil
            } else {
                item.manualInsets = clamped
            }
        }
    }

    func resetManualInsets(for id: UUID) {
        updateItem(id: id) { $0.manualInsets = nil }
    }

    func cleanupPreviewCache() {
        try? FileManager.default.removeItem(at: previewCacheDir)
    }

    // MARK: - Toast / Banner Notifications

    /// Displays a confirmation toast or persistent error banner.
    /// Success and info notices auto-dismiss after 3.5 seconds (resetting cleanly if replaced);
    /// error banners remain visible until dismissed by the user.
    func showBanner(
        _ message: String,
        kind: AppBanner.Kind,
        autoDismissAfter overrideDuration: Duration? = nil
    ) {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil

        let next = AppBanner(message: message, kind: kind)
        banner = next

        let timeout: Duration? = (kind == .error) ? nil : (overrideDuration ?? kind.defaultAutoDismiss)
        guard let timeout else { return }

        let targetID = next.id
        bannerDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                if self?.banner?.id == targetID {
                    self?.banner = nil
                    self?.bannerDismissTask = nil
                }
            } catch {
                // Cancelled by a newer banner or manual dismissal.
            }
        }
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        banner = nil
    }

    // MARK: - Helpers

    func updateItem(id: UUID, _ mutate: (inout QueueItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
        syncMenu()
    }

    private func recomputeParentContextLabels() {
        let labels = MKVFileDiscovery.parentContextLabels(for: items.map(\.url))
        for idx in items.indices {
            items[idx].parentContext = labels[items[idx].canonicalPath]
        }
    }

    func syncMenu() {
        MenuState.shared.sync(from: self)
    }
}
