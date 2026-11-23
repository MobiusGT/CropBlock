import Foundation

public enum MatroskaReadError: Error, LocalizedError, Equatable {
    case unreadableFile(String)
    case notMatroskaFile
    case missingSegment
    case missingVideoTrack

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let detail): "Unable to read MKV file: \(detail)"
        case .notMatroskaFile: "File does not have a valid Matroska (EBML) header."
        case .missingSegment: "Matroska file is missing a Segment element."
        case .missingVideoTrack: "No video track was found in the Matroska header."
        }
    }
}

/// Pure-Swift Matroska EBML header reader that extracts track v1 Video properties in O(1) seek time,
/// including MKVs where `Tracks` is stored at the end of the file via `SeekHead` (and chained `SeekHead`).
public enum MatroskaHeaderReader {
    // EBML / Matroska Element IDs (raw encoded VINT bytes)
    private static let idEBML: UInt32 = 0x1A45DFA3
    private static let idSegment: UInt32 = 0x18538067
    private static let idSeekHead: UInt32 = 0x114D9B74
    private static let idSeek: UInt32 = 0x4DBB
    private static let idSeekID: UInt32 = 0x53AB
    private static let idSeekPosition: UInt32 = 0x53AC
    private static let idTracks: UInt32 = 0x1654AE6B
    private static let idCluster: UInt32 = 0x1F43B675
    private static let idTrackEntry: UInt32 = 0xAE
    private static let idTrackType: UInt32 = 0x83
    private static let idVideo: UInt32 = 0xE0

    // Video sub-elements
    private static let idPixelWidth: UInt32 = 0xB0
    private static let idPixelHeight: UInt32 = 0xBA
    private static let idPixelCropBottom: UInt32 = 0x54AA
    private static let idPixelCropTop: UInt32 = 0x54BB
    private static let idPixelCropLeft: UInt32 = 0x54CC
    private static let idPixelCropRight: UInt32 = 0x54DD
    private static let idDisplayWidth: UInt32 = 0x54B0
    private static let idDisplayUnit: UInt32 = 0x54B2
    private static let idDisplayHeight: UInt32 = 0x54BA

    /// Quick EBML magic check (`0x1A 0x45 0xDF 0xA3`).
    public static func hasEBMLMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 4), bytes.count == 4 else { return false }
        return bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3
    }

    /// Reads the first video track's (`track:v1`, `TrackType == 1`) Matroska Video header.
    public static func readVideoHeader(at url: URL) throws -> MatroskaVideoHeader {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw MatroskaReadError.unreadableFile(error.localizedDescription)
        }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
        } catch {
            throw MatroskaReadError.unreadableFile(error.localizedDescription)
        }

        // 1. Validate EBML header at offset 0 and skip over it.
        guard let ebmlHeader = readElementHeader(from: handle, limit: fileSize),
              ebmlHeader.id == idEBML,
              let ebmlSize = ebmlHeader.size else {
            throw MatroskaReadError.notMatroskaFile
        }
        let afterEBML = ebmlHeader.dataOffset + ebmlSize
        guard afterEBML < fileSize else { throw MatroskaReadError.missingSegment }

        // 2. Locate Segment element.
        var cursor = afterEBML
        var segmentDataOffset: UInt64?
        var segmentEnd: UInt64 = fileSize

        var topElementsScanned = 0
        while cursor < fileSize && topElementsScanned < 32 {
            topElementsScanned += 1
            try? handle.seek(toOffset: cursor)
            guard let header = readElementHeader(from: handle, limit: fileSize) else { break }
            if header.id == idSegment {
                segmentDataOffset = header.dataOffset
                if let segSize = header.size {
                    segmentEnd = min(fileSize, header.dataOffset + segSize)
                } else {
                    segmentEnd = fileSize
                }
                break
            }
            guard let size = header.size else { break }
            cursor = header.dataOffset + size
        }

        guard let segOrigin = segmentDataOffset else {
            throw MatroskaReadError.missingSegment
        }

        // 3. Scan top-level Segment elements. Follow SeekHead when Tracks sits after Cluster.
        var seekedTracksOffsets: [UInt64] = []
        var secondarySeekHeads: [UInt64] = []
        var visitedSeekHeads: Set<UInt64> = []
        var pos = segOrigin
        var scannedTopLevel = 0
        var hitCluster = false

        while pos < segmentEnd && scannedTopLevel < 2000 {
            scannedTopLevel += 1
            try? handle.seek(toOffset: pos)
            guard let elem = readElementHeader(from: handle, limit: segmentEnd) else { break }

            if elem.id == idTracks {
                if let size = elem.size, size <= 32 * 1024 * 1024,
                   let data = readBytes(from: handle, at: elem.dataOffset, count: Int(size)) {
                    if let video = parseTracks(data) {
                        return video
                    }
                }
                throw MatroskaReadError.missingVideoTrack
            }

            if elem.id == idSeekHead {
                visitedSeekHeads.insert(pos)
                if let size = elem.size, size <= 4 * 1024 * 1024,
                   let data = readBytes(from: handle, at: elem.dataOffset, count: Int(size)) {
                    let entries = parseSeekHead(data)
                    for entry in entries {
                        let absolute = segOrigin &+ entry.position
                        guard absolute < segmentEnd else { continue }
                        if entry.seekID == idTracks {
                            seekedTracksOffsets.append(absolute)
                        } else if entry.seekID == idSeekHead, !visitedSeekHeads.contains(absolute) {
                            secondarySeekHeads.append(absolute)
                        }
                    }
                }
            }

            if elem.id == idCluster {
                hitCluster = true
                // Jump immediately via SeekHead if we already discovered Tracks or a secondary SeekHead.
                if let header = tryResolveViaSeekHeads(
                    handle: handle,
                    segOrigin: segOrigin,
                    segmentEnd: segmentEnd,
                    tracksOffsets: &seekedTracksOffsets,
                    secondarySeekHeads: &secondarySeekHeads,
                    visitedSeekHeads: &visitedSeekHeads
                ) {
                    return header
                }
            }

            // Advance past this element using O(1) seek (never reading Cluster payloads).
            guard let size = elem.size else {
                // Unknown-size Cluster (live/streaming mux) with no SeekHead -> cannot skip blindly.
                break
            }
            let next = elem.dataOffset + size
            if next <= pos { break }
            pos = next

            // Guard: if we already passed Cluster without SeekHead, cap top-level skips to avoid huge scans.
            if hitCluster && scannedTopLevel > 5000 { break }
        }

        // Final check in case SeekHead entries were collected right before EOF.
        if let header = tryResolveViaSeekHeads(
            handle: handle,
            segOrigin: segOrigin,
            segmentEnd: segmentEnd,
            tracksOffsets: &seekedTracksOffsets,
            secondarySeekHeads: &secondarySeekHeads,
            visitedSeekHeads: &visitedSeekHeads
        ) {
            return header
        }

        throw MatroskaReadError.missingVideoTrack
    }

    // MARK: - SeekHead Resolution

    private struct SeekEntry {
        let seekID: UInt32
        let position: UInt64
    }

    private static func tryResolveViaSeekHeads(
        handle: FileHandle,
        segOrigin: UInt64,
        segmentEnd: UInt64,
        tracksOffsets: inout [UInt64],
        secondarySeekHeads: inout [UInt64],
        visitedSeekHeads: inout Set<UInt64>
    ) -> MatroskaVideoHeader? {
        // First try any directly known Tracks offsets.
        while !tracksOffsets.isEmpty {
            let target = tracksOffsets.removeFirst()
            if let video = readTracksAt(offset: target, handle: handle, limit: segmentEnd) {
                return video
            }
        }

        // Follow chained SeekHeads (e.g., primary SeekHead at start -> secondary SeekHead at end -> Tracks).
        var depth = 0
        while !secondarySeekHeads.isEmpty && depth < 8 {
            depth += 1
            let seekHeadOffset = secondarySeekHeads.removeFirst()
            guard !visitedSeekHeads.contains(seekHeadOffset), seekHeadOffset < segmentEnd else { continue }
            visitedSeekHeads.insert(seekHeadOffset)
            try? handle.seek(toOffset: seekHeadOffset)
            guard let elem = readElementHeader(from: handle, limit: segmentEnd),
                  elem.id == idSeekHead,
                  let size = elem.size, size <= 4 * 1024 * 1024,
                  let data = readBytes(from: handle, at: elem.dataOffset, count: Int(size)) else {
                continue
            }
            for entry in parseSeekHead(data) {
                let absolute = segOrigin &+ entry.position
                guard absolute < segmentEnd else { continue }
                if entry.seekID == idTracks {
                    if let video = readTracksAt(offset: absolute, handle: handle, limit: segmentEnd) {
                        return video
                    }
                } else if entry.seekID == idSeekHead, !visitedSeekHeads.contains(absolute) {
                    secondarySeekHeads.append(absolute)
                }
            }
        }
        return nil
    }

    private static func readTracksAt(offset: UInt64, handle: FileHandle, limit: UInt64) -> MatroskaVideoHeader? {
        guard offset < limit else { return nil }
        try? handle.seek(toOffset: offset)
        guard let elem = readElementHeader(from: handle, limit: limit),
              elem.id == idTracks,
              let size = elem.size, size <= 32 * 1024 * 1024,
              let data = readBytes(from: handle, at: elem.dataOffset, count: Int(size)) else {
            return nil
        }
        return parseTracks(data)
    }

    private static func parseSeekHead(_ data: Data) -> [SeekEntry] {
        var entries: [SeekEntry] = []
        var offset = 0
        while offset < data.count {
            guard let elem = readElement(in: data, at: offset) else { break }
            if elem.id == idSeek {
                let seekData = data[elem.dataRange]
                var innerOffset = seekData.startIndex
                var foundID: UInt32?
                var foundPos: UInt64?
                while innerOffset < seekData.endIndex {
                    guard let child = readElement(in: data, at: innerOffset) else { break }
                    if child.id == idSeekID, child.dataRange.count <= 4 {
                        foundID = UInt32(decodeBigEndianUInt(data[child.dataRange]))
                    } else if child.id == idSeekPosition, child.dataRange.count <= 8 {
                        foundPos = decodeBigEndianUInt(data[child.dataRange])
                    }
                    innerOffset = child.nextOffset
                }
                if let seekID = foundID, let position = foundPos {
                    entries.append(SeekEntry(seekID: seekID, position: position))
                }
            }
            offset = elem.nextOffset
        }
        return entries
    }

    // MARK: - Tracks & Video Parsing

    private static func parseTracks(_ data: Data) -> MatroskaVideoHeader? {
        var offset = 0
        while offset < data.count {
            guard let elem = readElement(in: data, at: offset) else { break }
            if elem.id == idTrackEntry {
                if let header = parseTrackEntry(data, range: elem.dataRange) {
                    return header
                }
            }
            offset = elem.nextOffset
        }
        return nil
    }

    private static func parseTrackEntry(_ data: Data, range: Range<Int>) -> MatroskaVideoHeader? {
        var offset = range.lowerBound
        var trackType: UInt64?
        var videoRange: Range<Int>?

        while offset < range.upperBound {
            guard let child = readElement(in: data, at: offset) else { break }
            if child.id == idTrackType {
                trackType = decodeBigEndianUInt(data[child.dataRange])
            } else if child.id == idVideo {
                videoRange = child.dataRange
            }
            offset = child.nextOffset
        }

        // TrackType 1 = video
        guard trackType == 1, let videoRange else { return nil }
        return parseVideoElement(data, range: videoRange)
    }

    private static func parseVideoElement(_ data: Data, range: Range<Int>) -> MatroskaVideoHeader {
        var header = MatroskaVideoHeader()
        var offset = range.lowerBound

        while offset < range.upperBound {
            guard let child = readElement(in: data, at: offset) else { break }
            let val = Int(decodeBigEndianUInt(data[child.dataRange]))
            switch child.id {
            case idPixelWidth: header.pixelWidth = val
            case idPixelHeight: header.pixelHeight = val
            case idPixelCropLeft: header.pixelCropLeft = val
            case idPixelCropRight: header.pixelCropRight = val
            case idPixelCropTop: header.pixelCropTop = val
            case idPixelCropBottom: header.pixelCropBottom = val
            case idDisplayWidth: header.displayWidth = val
            case idDisplayHeight: header.displayHeight = val
            case idDisplayUnit: header.displayUnit = val
            default: break
            }
            offset = child.nextOffset
        }
        return header
    }

    // MARK: - Low-Level EBML VINT Primitives

    private struct FileElementHeader {
        let id: UInt32
        /// `nil` indicates an unknown-length EBML element (all data bits 1).
        let size: UInt64?
        let dataOffset: UInt64
    }

    private struct MemoryElement {
        let id: UInt32
        let dataRange: Range<Int>
        let nextOffset: Int
    }

    private static func readElementHeader(from handle: FileHandle, limit: UInt64) -> FileElementHeader? {
        guard let startOffset = try? handle.offset(), startOffset < limit else { return nil } // grid: ok FileHandle.offset()
        let readLen = Int(min(12, limit - startOffset))
        guard readLen >= 2, let chunk = try? handle.read(upToCount: readLen), chunk.count >= 2 else { return nil }

        guard let (id, idLen) = decodeElementID(in: chunk, at: 0),
              idLen < chunk.count,
              let (size, sizeLen) = decodeDataSize(in: chunk, at: idLen) else {
            return nil
        }
        let dataOffset = startOffset + UInt64(idLen + sizeLen)
        return FileElementHeader(id: id, size: size, dataOffset: dataOffset)
    }

    private static func readBytes(from handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        guard count >= 0 else { return nil }
        if count == 0 { return Data() }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: count)
            return data?.count == count ? data : nil
        } catch {
            return nil
        }
    }

    private static func readElement(in data: Data, at offset: Int) -> MemoryElement? {
        guard offset < data.count else { return nil }
        guard let (id, idLen) = decodeElementID(in: data, at: offset),
              offset + idLen < data.count,
              let (sizeOpt, sizeLen) = decodeDataSize(in: data, at: offset + idLen),
              let size = sizeOpt else {
            return nil
        }
        let dataStart = offset + idLen + sizeLen
        let dataEnd = min(data.count, dataStart + Int(size))
        guard dataStart <= dataEnd else { return nil }
        return MemoryElement(id: id, dataRange: dataStart..<dataEnd, nextOffset: dataEnd)
    }

    /// Decodes an EBML Element ID (1–4 bytes, preserving the leading length-marker bit).
    private static func decodeElementID(in data: Data, at offset: Int) -> (UInt32, Int)? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        guard first != 0 else { return nil }
        let length = first.leadingZeroBitCount + 1
        guard length >= 1, length <= 4, offset + length <= data.count else { return nil }
        var value: UInt32 = 0
        for i in 0..<length {
            value = (value << 8) | UInt32(data[offset + i])
        }
        return (value, length)
    }

    /// Decodes an EBML Data Size VINT (1–8 bytes, stripping the leading length-marker bit).
    /// Returns `nil` for the size when all payload bits are 1 (unknown/streaming size).
    private static func decodeDataSize(in data: Data, at offset: Int) -> (UInt64?, Int)? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        guard first != 0 else { return nil }
        let length = first.leadingZeroBitCount + 1
        guard length >= 1, length <= 8, offset + length <= data.count else { return nil }
        let mask: UInt8 = (1 << (8 - length)) - 1
        var value = UInt64(first & mask)
        var allOnes = UInt64(mask)
        for i in 1..<length {
            value = (value << 8) | UInt64(data[offset + i])
            allOnes = (allOnes << 8) | 0xFF
        }
        if value == allOnes {
            return (nil, length)
        }
        return (value, length)
    }

    private static func decodeBigEndianUInt(_ slice: Data.SubSequence) -> UInt64 {
        var result: UInt64 = 0
        for byte in slice {
            result = (result << 8) | UInt64(byte)
        }
        return result
    }
}
