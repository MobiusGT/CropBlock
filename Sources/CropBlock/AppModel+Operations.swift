import Foundation
import CropBlockKit

/// Bounded concurrent scanning, single/batch lossless apply, and 1-click restore orchestration.
extension AppModel {

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
                    "Stopped batch apply after \(succeeded) \(succeeded == 1 ? "file" : "files").",
                    kind: .info
                )
            } else if failed > 0 {
                self.showBanner(
                    "Applied crop to \(succeeded) \(succeeded == 1 ? "file" : "files"); \(failed) failed—select error rows for details.",
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
