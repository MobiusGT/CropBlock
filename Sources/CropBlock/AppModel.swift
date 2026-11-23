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
    var detectionSettings: DetectionSettings

    var showsToolSetupSheet = false
    var showsCompatibilityPopover = false
    var showsCropOverlay = true { didSet { syncMenu() } }
    var isDropTargeted = false
    var bannerMessage: String?

    var isScanning = false { didSet { syncMenu() } }
    var activeScanCount = 0
    var isBatchApplying = false { didSet { syncMenu() } }
    var batchApplyCompleted = 0
    var batchApplyTotal = 0

    @ObservationIgnored let backend: any CropBackend = MKVHeaderCropBackend()
    @ObservationIgnored let receiptStore: ReceiptStore
    @ObservationIgnored let previewCacheDir: URL
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var batchApplyTask: Task<Void, Never>?
    @ObservationIgnored private var hasCheckedInitialTools = false

    private enum DefaultsKey {
        static let customFFmpeg = "tools.custom.ffmpeg"
        static let customFFprobe = "tools.custom.ffprobe"
        static let customMkvpropedit = "tools.custom.mkvpropedit"
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
        self.detectionSettings = .default
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

    var readyToApplyIDs: [UUID] {
        let candidates = items.map { item -> BatchCandidate in
            let kind: BatchEligibilityStatus
            switch item.status {
            case .pending: kind = .pending
            case .scanning: kind = .scanning
            case .detected: kind = .detected
            case .noBars: kind = .noBars
            case .variableAR: kind = .variableAR
            case .cropped: kind = .cropped
            case .error: kind = .error
            }
            return BatchCandidate(
                id: item.id,
                status: kind,
                hasNonZeroInsets: !item.activeInsets.isZero,
                variableARConfirmed: item.variableARConfirmed,
                isApplying: item.isApplying
            )
        }
        return BatchApplyPlanner.eligibleIDs(from: candidates)
    }

    var readyToApplyCount: Int { readyToApplyIDs.count }

    func plan(for item: QueueItem) -> CropApplyPlan? {
        guard let inspection = item.inspection else { return nil }
        return backend.buildPlan(for: inspection, insets: item.activeInsets)
    }

    // MARK: - Tool Discovery

    func startupCheck() async {
        guard !hasCheckedInitialTools else { return }
        hasCheckedInitialTools = true
        await refreshTools(presentSheetIfMissing: !Snapshot.isActive && !SelfTest.requested)
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
                bannerMessage = "No MKV files found in the dropped items."
            }
            return
        }

        bannerMessage = nil
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
            let count = item.detection?.samples.count ?? 0
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

    // MARK: - Bounded Concurrent Scanning

    func scanAllPending() {
        let pendingIDs = items.filter { $0.status == .pending }.map(\.id)
        guard !pendingIDs.isEmpty else { return }
        startScanBatch(ids: pendingIDs)
    }

    func rescanItem(id: UUID) {
        updateItem(id: id) {
            $0.status = .pending
            $0.manualInsets = nil
            $0.variableARConfirmed = false
        }
        startScanBatch(ids: [id])
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        activeScanCount = 0
        for idx in items.indices where items[idx].status == .scanning {
            items[idx].status = .pending
        }
    }

    private func startScanBatch(ids: [UUID]) {
        guard tools.ffmpegURL != nil && tools.ffprobeURL != nil else {
            showsToolSetupSheet = true
            return
        }

        scanTask?.cancel()
        let settings = detectionSettings
        let resolvedTools = tools
        let cacheDir = previewCacheDir
        let maxConcurrency = settings.maxConcurrentScans

        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                var iterator = ids.makeIterator()
                var running = 0

                @MainActor
                func enqueueNext() {
                    while running < maxConcurrency, let nextID = iterator.next() {
                        guard let target = self.items.first(where: { $0.id == nextID }) else { continue }
                        running += 1
                        self.activeScanCount = running
                        self.updateItem(id: nextID) { $0.status = .scanning }
                        let fileURL = target.url

                        group.addTask { [weak self] in
                            await self?.performSingleScan(
                                id: nextID,
                                url: fileURL,
                                settings: settings,
                                tools: resolvedTools,
                                cacheDir: cacheDir
                            )
                        }
                    }
                }

                enqueueNext()
                for await _ in group {
                    running = max(0, running - 1)
                    self.activeScanCount = running
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    enqueueNext()
                }
            }
            if !Task.isCancelled {
                self.isScanning = false
                self.activeScanCount = 0
            }
        }
    }

    private func performSingleScan(
        id: UUID,
        url: URL,
        settings: DetectionSettings,
        tools: ResolvedTools,
        cacheDir: URL
    ) async {
        do {
            let result = try await VideoScanner.scan(
                url: url,
                settings: settings,
                tools: tools,
                previewCacheDirectory: cacheDir
            )
            let existingReceipt = await receiptStore.receipt(for: url)
            let newStatus: QueueItemStatus
            if result.detection.hasVariableAR {
                newStatus = .variableAR
            } else if result.detection.hasBars {
                if result.inspection.currentHeader.effectiveCropInsets == result.detection.proposedInsets {
                    newStatus = .cropped
                } else {
                    newStatus = .detected
                }
            } else {
                newStatus = .noBars
            }

            let defaultSampleIdx = result.detection.samples.count >= 2 ? 1 : 0
            updateItem(id: id) { item in
                item.inspection = result.inspection
                item.detection = result.detection
                item.receipt = existingReceipt
                item.selectedSampleIndex = defaultSampleIdx
                item.status = newStatus
            }
        } catch is CancellationError {
            updateItem(id: id) { if $0.status == .scanning { $0.status = .pending } }
        } catch ProcessRunnerError.cancelled {
            updateItem(id: id) { if $0.status == .scanning { $0.status = .pending } }
        } catch {
            updateItem(id: id) { item in
                item.status = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Lossless Apply & 1-Click Restore

    func applyCrop(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              item.canApply else {
            return
        }
        guard tools.mkvpropeditURL != nil else {
            showsToolSetupSheet = true
            return
        }
        Task {
            await performSingleApply(id: id)
        }
    }

    func applyAllReady() {
        let targetIDs = readyToApplyIDs
        guard !targetIDs.isEmpty else { return }
        guard tools.mkvpropeditURL != nil else {
            showsToolSetupSheet = true
            return
        }

        batchApplyTask?.cancel()
        isBatchApplying = true
        batchApplyCompleted = 0
        batchApplyTotal = targetIDs.count
        bannerMessage = nil

        let maxConcurrency = 2
        batchApplyTask = Task { [weak self] in
            guard let self else { return }
            var succeeded = 0
            var failed = 0

            await withTaskGroup(of: Bool.self) { group in
                var iterator = targetIDs.makeIterator()
                var running = 0

                @MainActor
                func enqueueNext() {
                    while running < maxConcurrency, let nextID = iterator.next() {
                        running += 1
                        group.addTask { [weak self] in
                            guard let self else { return false }
                            return await self.performSingleApply(id: nextID)
                        }
                    }
                }

                enqueueNext()
                for await ok in group {
                    running = max(0, running - 1)
                    if ok { succeeded += 1 } else { failed += 1 }
                    self.batchApplyCompleted = succeeded + failed
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    enqueueNext()
                }
            }

            let cancelled = Task.isCancelled
            self.isBatchApplying = false
            self.batchApplyTotal = 0
            self.batchApplyCompleted = 0
            if cancelled {
                self.bannerMessage = "Stopped batch apply after \(succeeded) \(succeeded == 1 ? "file" : "files")."
            } else if failed > 0 {
                self.bannerMessage = "Applied crop to \(succeeded) \(succeeded == 1 ? "file" : "files"); \(failed) failed—select error rows for details."
            } else if succeeded > 0 {
                self.bannerMessage = "Applied crop to \(succeeded) \(succeeded == 1 ? "file" : "files")."
            }
        }
    }

    func stopBatchApply() {
        batchApplyTask?.cancel()
        batchApplyTask = nil
    }

    @discardableResult
    func performSingleApply(id: UUID) async -> Bool {
        guard let item = items.first(where: { $0.id == id }),
              item.canApply,
              let inspection = item.inspection,
              let plan = plan(for: item) else {
            return false
        }

        updateItem(id: id) { $0.isApplying = true }
        let targetURL = item.url
        let existingReceipt = item.receipt
        let currentTools = tools

        do {
            let receipt = try await backend.apply(
                plan: plan,
                inspection: inspection,
                to: targetURL,
                tools: currentTools,
                existingReceipt: existingReceipt
            )
            try await receiptStore.save(receipt)
            let refreshedHeader = (try? MatroskaHeaderReader.readVideoHeader(at: targetURL)) ?? inspection.currentHeader

            updateItem(id: id) { item in
                item.isApplying = false
                item.receipt = receipt
                item.inspection?.currentHeader = refreshedHeader
                item.status = .cropped
            }
            return true
        } catch {
            updateItem(id: id) { item in
                item.isApplying = false
                item.status = .error(error.localizedDescription)
            }
            return false
        }
    }

    func restoreOriginal(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              item.canRestore,
              let inspection = item.inspection else {
            return
        }
        guard tools.mkvpropeditURL != nil else {
            showsToolSetupSheet = true
            return
        }

        updateItem(id: id) { $0.isApplying = true }
        let targetURL = item.url
        let receipt = item.receipt
        let currentTools = tools

        Task {
            do {
                try await backend.restore(
                    receipt: receipt,
                    inspection: inspection,
                    to: targetURL,
                    tools: currentTools
                )
                try await receiptStore.remove(for: targetURL)
                let refreshedHeader = (try? MatroskaHeaderReader.readVideoHeader(at: targetURL)) ?? MatroskaVideoHeader()

                updateItem(id: id) { item in
                    item.isApplying = false
                    item.receipt = nil
                    item.inspection?.currentHeader = refreshedHeader
                    if let detection = item.detection {
                        if detection.hasVariableAR {
                            item.status = .variableAR
                        } else if detection.hasBars {
                            item.status = .detected
                        } else {
                            item.status = .noBars
                        }
                    } else {
                        item.status = .pending
                    }
                }
            } catch {
                updateItem(id: id) { item in
                    item.isApplying = false
                    item.status = .error(error.localizedDescription)
                }
            }
        }
    }

    func cleanupPreviewCache() {
        try? FileManager.default.removeItem(at: previewCacheDir)
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
