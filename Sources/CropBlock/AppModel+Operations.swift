import Foundation
import CropBlockKit

/// Bounded concurrent Standard & Deep scanning, single/batch lossless Crop All,
/// and 1-click restore orchestration.
extension AppModel {

    // MARK: - Bounded Concurrent Scanning (Standard & Deep)

    func scanAllPending() {
        let pendingIDs = items.filter { $0.status == .pending }.map(\.id)
        guard !pendingIDs.isEmpty else { return }
        startScanBatch(ids: pendingIDs, mode: .standard)
    }

    func rescanItem(id: UUID) {
        updateItem(id: id) {
            $0.status = .pending
            $0.manualInsets = nil
            $0.variableARConfirmed = false
        }
        startScanBatch(ids: [id], mode: .standard)
    }

    func deepScanItem(id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.isApplying else { return }
        updateItem(id: id) {
            $0.status = .scanning
            $0.activeScanMode = .deep
            $0.scanCompletedIntervals = 0
            $0.scanTotalIntervals = 0
            $0.manualInsets = nil
            $0.variableARConfirmed = false
        }
        startScanBatch(ids: [id], mode: .deep)
    }

    func deepScanAll() {
        let targetIDs = deepScanEligibleIDs
        guard !targetIDs.isEmpty else { return }
        for id in targetIDs {
            updateItem(id: id) {
                $0.status = .pending
                $0.manualInsets = nil
                $0.variableARConfirmed = false
            }
        }
        startScanBatch(ids: targetIDs, mode: .deep)
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        activeScanCount = 0
        batchScanCompleted = 0
        batchScanTotal = 0
        for idx in items.indices where items[idx].status == .scanning {
            items[idx].activeScanMode = nil
            items[idx].scanCompletedIntervals = 0
            items[idx].scanTotalIntervals = 0
            if let existing = items[idx].detection {
                items[idx].status = statusForDetection(existing, currentHeader: items[idx].inspection?.currentHeader)
            } else {
                items[idx].status = .pending
            }
        }
    }

    private func startScanBatch(ids: [UUID], mode: ScanMode) {
        guard tools.ffmpegURL != nil && tools.ffprobeURL != nil else {
            showsToolSetupSheet = true
            return
        }

        scanTask?.cancel()
        let settings = detectionSettings
        let resolvedTools = tools
        let cacheDir = previewCacheDir
        let maxConcurrency = settings.maxConcurrentScans

        activeBatchScanMode = mode
        batchScanCompleted = 0
        batchScanTotal = ids.count
        isScanning = true

        scanTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0
            var succeeded = 0

            await withTaskGroup(of: Bool.self) { group in
                var iterator = ids.makeIterator()
                var running = 0

                @MainActor
                func enqueueNext() {
                    while running < maxConcurrency, let nextID = iterator.next() {
                        guard let target = self.items.first(where: { $0.id == nextID }) else { continue }
                        running += 1
                        self.activeScanCount = running
                        self.updateItem(id: nextID) { item in
                            item.status = .scanning
                            item.activeScanMode = mode
                            item.scanCompletedIntervals = 0
                            item.scanTotalIntervals = 0
                        }
                        let fileURL = target.url

                        group.addTask { [weak self] in
                            guard let self else { return false }
                            return await self.performSingleScan(
                                id: nextID,
                                url: fileURL,
                                settings: settings,
                                tools: resolvedTools,
                                cacheDir: cacheDir,
                                mode: mode
                            )
                        }
                    }
                }

                enqueueNext()
                for await ok in group {
                    running = max(0, running - 1)
                    completed += 1
                    if ok { succeeded += 1 }
                    self.activeScanCount = running
                    self.batchScanCompleted = completed
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    enqueueNext()
                }
            }

            let cancelled = Task.isCancelled
            self.isScanning = false
            self.activeScanCount = 0
            self.batchScanCompleted = 0
            self.batchScanTotal = 0

            if mode == .deep {
                if cancelled {
                    self.showBanner("Deep Scan stopped.", kind: .info)
                } else if ids.count == 1, succeeded == 1,
                          let item = self.items.first(where: { $0.id == ids[0] }),
                          let label = item.deepScanBadgeLabel {
                    self.showBanner("\(label) complete for \(item.fileName).", kind: .success)
                } else if ids.count > 1 && succeeded > 0 {
                    self.showBanner(
                        "Deep Scan complete for \(succeeded) \(succeeded == 1 ? "file" : "files").",
                        kind: .success
                    )
                }
            }
        }
    }

    private func performSingleScan(
        id: UUID,
        url: URL,
        settings: DetectionSettings,
        tools: ResolvedTools,
        cacheDir: URL,
        mode: ScanMode
    ) async -> Bool {
        do {
            let result = try await VideoScanner.scan(
                url: url,
                settings: settings,
                tools: tools,
                previewCacheDirectory: cacheDir,
                mode: mode
            ) { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.updateItem(id: id) { item in
                        item.scanCompletedIntervals = completed
                        item.scanTotalIntervals = total
                    }
                }
            }
            let existingReceipt = await receiptStore.receipt(for: url)
            let newStatus = statusForDetection(result.detection, currentHeader: result.inspection.currentHeader)
            let previewCount = result.detection.previewableSamples.count
            let defaultSampleIdx = previewCount >= 2 ? previewCount / 2 : 0

            updateItem(id: id) { item in
                item.inspection = result.inspection
                item.detection = result.detection
                item.receipt = existingReceipt
                item.selectedSampleIndex = defaultSampleIdx
                item.activeScanMode = nil
                item.scanCompletedIntervals = 0
                item.scanTotalIntervals = 0
                item.status = newStatus
            }
            return true
        } catch is CancellationError {
            restoreStatusAfterCancel(id: id)
            return false
        } catch ProcessRunnerError.cancelled {
            restoreStatusAfterCancel(id: id)
            return false
        } catch {
            updateItem(id: id) { item in
                item.activeScanMode = nil
                item.scanCompletedIntervals = 0
                item.scanTotalIntervals = 0
                item.status = .error(error.localizedDescription)
            }
            return false
        }
    }

    private func restoreStatusAfterCancel(id: UUID) {
        updateItem(id: id) { item in
            guard item.status == .scanning else { return }
            item.activeScanMode = nil
            item.scanCompletedIntervals = 0
            item.scanTotalIntervals = 0
            if let existing = item.detection {
                item.status = statusForDetection(existing, currentHeader: item.inspection?.currentHeader)
            } else {
                item.status = .pending
            }
        }
    }

    private func statusForDetection(_ detection: CropDetectionResult, currentHeader: MatroskaVideoHeader?) -> QueueItemStatus {
        if detection.hasVariableAR {
            return .variableAR
        }
        if detection.hasBars {
            if let header = currentHeader, header.effectiveCropInsets == detection.proposedInsets {
                return .cropped
            }
            return .detected
        }
        return .noBars
    }

    // MARK: - Lossless Apply, Crop All & 1-Click Restore

    func applyCrop(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              item.canApply else {
            return
        }
        guard tools.mkvpropeditURL != nil else {
            showsToolSetupSheet = true
            return
        }
        let fileName = item.fileName
        Task {
            let ok = await performSingleApply(id: id)
            if ok {
                showBanner("Crop applied to \(fileName).", kind: .success)
            } else if let err = items.first(where: { $0.id == id })?.status.errorMessage {
                showBanner(err, kind: .error)
            }
        }
    }

    func cropAll() {
        let targetIDs = cropAllReadyIDs
        guard !targetIDs.isEmpty else { return }
        guard tools.mkvpropeditURL != nil else {
            showsToolSetupSheet = true
            return
        }

        batchApplyTask?.cancel()
        isBatchApplying = true
        batchApplyCompleted = 0
        batchApplyTotal = targetIDs.count
        dismissBanner()

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
                self.showBanner(
                    "Stopped Crop All after \(succeeded) \(succeeded == 1 ? "file" : "files").",
                    kind: .info
                )
            } else if failed > 0 {
                self.showBanner(
                    "Cropped \(succeeded) \(succeeded == 1 ? "file" : "files"); \(failed) failed—select error rows for details.",
                    kind: .error
                )
            } else if succeeded > 0 {
                self.showBanner(
                    "Crops successfully applied to \(succeeded) \(succeeded == 1 ? "file" : "files").",
                    kind: .success
                )
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
            await refreshReceiptCount()
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
                await refreshReceiptCount()
                let refreshedHeader = (try? MatroskaHeaderReader.readVideoHeader(at: targetURL)) ?? MatroskaVideoHeader()

                updateItem(id: id) { item in
                    item.isApplying = false
                    item.receipt = nil
                    item.inspection?.currentHeader = refreshedHeader
                    if let detection = item.detection {
                        item.status = statusForDetection(detection, currentHeader: refreshedHeader)
                    } else {
                        item.status = .pending
                    }
                }
                showBanner("Restored original headers for \(targetURL.lastPathComponent).", kind: .success)
            } catch {
                updateItem(id: id) { item in
                    item.isApplying = false
                    item.status = .error(error.localizedDescription)
                }
                showBanner(error.localizedDescription, kind: .error)
            }
        }
    }
}
