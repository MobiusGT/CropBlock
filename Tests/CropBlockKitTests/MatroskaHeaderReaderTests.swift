import Foundation
import Testing
@testable import CropBlockKit

/// Helper for synthesizing valid EBML / Matroska binary fixtures in unit tests.
private enum EBMLFixtureBuilder {
    static func idBytes(_ id: UInt32) -> Data {
        if id <= 0xFF { return Data([UInt8(id)]) }
        if id <= 0xFFFF { return Data([UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)]) }
        if id <= 0xFFFFFF { return Data([UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)]) }
        return Data([UInt8((id >> 24) & 0xFF), UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)])
    }

    static func vintSize(_ value: Int) -> Data {
        let v = UInt64(value)
        if v < 0x7F {
            return Data([UInt8(0x80 | v)])
        } else if v < 0x3FFF {
            return Data([UInt8(0x40 | (v >> 8)), UInt8(v & 0xFF)])
        } else {
            return Data([
                UInt8(0x10 | ((v >> 24) & 0x0F)),
                UInt8((v >> 16) & 0xFF),
                UInt8((v >> 8) & 0xFF),
                UInt8(v & 0xFF),
            ])
        }
    }

    static func uintBytes(_ value: UInt64) -> Data {
        if value == 0 { return Data([0]) }
        var bytes: [UInt8] = []
        var v = value
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return Data(bytes)
    }

    static func element(_ id: UInt32, payload: Data) -> Data {
        var out = idBytes(id)
        out.append(vintSize(payload.count))
        out.append(payload)
        return out
    }

    static func uintElement(_ id: UInt32, value: UInt64) -> Data {
        element(id, payload: uintBytes(value))
    }

    static func ebmlHeader() -> Data {
        // Minimal valid EBML header containing DocType = "matroska"
        let docType = element(0x4282, payload: Data("matroska".utf8))
        return element(0x1A45DFA3, payload: docType)
    }

    static func tracksElement(
        pixelWidth: UInt64,
        pixelHeight: UInt64,
        cropTop: UInt64? = nil,
        cropBottom: UInt64? = nil,
        cropLeft: UInt64? = nil,
        cropRight: UInt64? = nil,
        displayWidth: UInt64? = nil,
        displayHeight: UInt64? = nil,
        displayUnit: UInt64? = nil,
        includeLeadingAudioTrack: Bool = true
    ) -> Data {
        var tracksPayload = Data()
        if includeLeadingAudioTrack {
            // Track 1: audio (TrackType = 2) so we prove TrackType == 1 filtering works
            let audioTrack = element(0xAE, payload: uintElement(0x83, value: 2))
            tracksPayload.append(audioTrack)
        }

        var videoPayload = Data()
        videoPayload.append(uintElement(0xB0, value: pixelWidth))
        videoPayload.append(uintElement(0xBA, value: pixelHeight))
        if let v = cropBottom { videoPayload.append(uintElement(0x54AA, value: v)) }
        if let v = cropTop { videoPayload.append(uintElement(0x54BB, value: v)) }
        if let v = cropLeft { videoPayload.append(uintElement(0x54CC, value: v)) }
        if let v = cropRight { videoPayload.append(uintElement(0x54DD, value: v)) }
        if let v = displayWidth { videoPayload.append(uintElement(0x54B0, value: v)) }
        if let v = displayUnit { videoPayload.append(uintElement(0x54B2, value: v)) }
        if let v = displayHeight { videoPayload.append(uintElement(0x54BA, value: v)) }

        var videoTrackPayload = Data()
        videoTrackPayload.append(uintElement(0x83, value: 1)) // TrackType = 1 (video)
        videoTrackPayload.append(element(0xE0, payload: videoPayload))
        tracksPayload.append(element(0xAE, payload: videoTrackPayload))

        return element(0x1654AE6B, payload: tracksPayload)
    }

    static func seekEntry(targetID: UInt32, segmentRelativePosition: UInt64) -> Data {
        var payload = Data()
        payload.append(element(0x53AB, payload: idBytes(targetID)))
        payload.append(uintElement(0x53AC, value: segmentRelativePosition))
        return element(0x4DBB, payload: payload)
    }

    static func writeTemp(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cb-ebml-\(UUID().uuidString).mkv")
        try data.write(to: url)
        return url
    }
}

@Suite("MatroskaHeaderReader EBML parsing")
struct MatroskaHeaderReaderTests {

    @Test("Parses Tracks before Cluster and distinguishes absent vs explicit zero fields")
    func standardLayoutTracksBeforeCluster() throws {
        let tracks = EBMLFixtureBuilder.tracksElement(
            pixelWidth: 1920,
            pixelHeight: 1080,
            cropTop: 0,
            displayWidth: 1920,
            displayHeight: 1080
        )
        let cluster = EBMLFixtureBuilder.element(0x1F43B675, payload: Data(repeating: 0xAA, count: 256))
        var segmentPayload = Data()
        segmentPayload.append(tracks)
        segmentPayload.append(cluster)

        var file = EBMLFixtureBuilder.ebmlHeader()
        file.append(EBMLFixtureBuilder.element(0x18538067, payload: segmentPayload))

        let url = try EBMLFixtureBuilder.writeTemp(file)
        defer { try? FileManager.default.removeItem(at: url) }

        let header = try MatroskaHeaderReader.readVideoHeader(at: url)
        #expect(header.pixelWidth == 1920)
        #expect(header.pixelHeight == 1080)
        #expect(header.pixelCropTop == 0)
        #expect(header.pixelCropBottom == nil) // absent stays nil
        #expect(header.pixelCropLeft == nil)
        #expect(header.pixelCropRight == nil)
        #expect(header.displayWidth == 1920)
        #expect(header.displayHeight == 1080)
        #expect(header.displayUnit == nil)
    }

    @Test("Follows SeekHead when Tracks sits at the end of the file after Cluster")
    func tracksAtEndOfFileViaSeekHead() throws {
        let cluster = EBMLFixtureBuilder.element(0x1F43B675, payload: Data(repeating: 0x55, count: 8192))
        let tracks = EBMLFixtureBuilder.tracksElement(
            pixelWidth: 3840,
            pixelHeight: 2160,
            cropTop: 276,
            cropBottom: 276,
            cropLeft: 0,
            cropRight: 0,
            displayWidth: 3840,
            displayHeight: 1608,
            displayUnit: 0
        )

        // Compute exact SeekHead size so SeekPosition points precisely to Tracks after Cluster.
        // Start with a 2-byte SeekPosition estimate (cluster > 256 bytes) and stabilize length.
        var seekHead = Data()
        var tracksOffset: UInt64 = 0
        for _ in 0..<4 {
            let candidateOffset = UInt64(seekHead.count + cluster.count)
            let newSeekHead = EBMLFixtureBuilder.element(
                0x114D9B74,
                payload: EBMLFixtureBuilder.seekEntry(targetID: 0x1654AE6B, segmentRelativePosition: candidateOffset)
            )
            seekHead = newSeekHead
            tracksOffset = UInt64(seekHead.count + cluster.count)
        }
        // Final SeekHead with converged offset
        seekHead = EBMLFixtureBuilder.element(
            0x114D9B74,
            payload: EBMLFixtureBuilder.seekEntry(targetID: 0x1654AE6B, segmentRelativePosition: tracksOffset)
        )
        #expect(UInt64(seekHead.count + cluster.count) == tracksOffset)

        var segmentPayload = Data()
        segmentPayload.append(seekHead)
        segmentPayload.append(cluster)
        segmentPayload.append(tracks)

        var file = EBMLFixtureBuilder.ebmlHeader()
        file.append(EBMLFixtureBuilder.element(0x18538067, payload: segmentPayload))

        let url = try EBMLFixtureBuilder.writeTemp(file)
        defer { try? FileManager.default.removeItem(at: url) }

        let header = try MatroskaHeaderReader.readVideoHeader(at: url)
        #expect(header.pixelWidth == 3840)
        #expect(header.pixelHeight == 2160)
        #expect(header.pixelCropTop == 276)
        #expect(header.pixelCropBottom == 276)
        #expect(header.displayWidth == 3840)
        #expect(header.displayHeight == 1608)
        #expect(header.displayUnit == 0)
    }

    @Test("Follows chained SeekHead (primary SeekHead -> secondary SeekHead at EOF -> Tracks)")
    func chainedSeekHeadToTracksAtEOF() throws {
        let cluster = EBMLFixtureBuilder.element(0x1F43B675, payload: Data(repeating: 0x33, count: 4096))
        let tracks = EBMLFixtureBuilder.tracksElement(
            pixelWidth: 1920,
            pixelHeight: 1080,
            cropTop: 140,
            cropBottom: 140
        )

        // Layout inside Segment: [seekHead1] [cluster] [tracks] [seekHead2]
        // seekHead1 points to seekHead2; seekHead2 points to tracks.
        var seekHead1 = Data()
        var seekHead2 = Data()
        for _ in 0..<6 {
            let tracksPos = UInt64(seekHead1.count + cluster.count)
            seekHead2 = EBMLFixtureBuilder.element(
                0x114D9B74,
                payload: EBMLFixtureBuilder.seekEntry(targetID: 0x1654AE6B, segmentRelativePosition: tracksPos)
            )
            let seekHead2Pos = UInt64(seekHead1.count + cluster.count + tracks.count)
            seekHead1 = EBMLFixtureBuilder.element(
                0x114D9B74,
                payload: EBMLFixtureBuilder.seekEntry(targetID: 0x114D9B74, segmentRelativePosition: seekHead2Pos)
            )
        }

        var segmentPayload = Data()
        segmentPayload.append(seekHead1)
        segmentPayload.append(cluster)
        segmentPayload.append(tracks)
        segmentPayload.append(seekHead2)

        var file = EBMLFixtureBuilder.ebmlHeader()
        file.append(EBMLFixtureBuilder.element(0x18538067, payload: segmentPayload))

        let url = try EBMLFixtureBuilder.writeTemp(file)
        defer { try? FileManager.default.removeItem(at: url) }

        let header = try MatroskaHeaderReader.readVideoHeader(at: url)
        #expect(header.pixelWidth == 1920)
        #expect(header.pixelHeight == 1080)
        #expect(header.pixelCropTop == 140)
        #expect(header.pixelCropBottom == 140)
    }

    @Test("Rejects non-Matroska files cleanly")
    func rejectsNonMKV() throws {
        let url = try EBMLFixtureBuilder.writeTemp(Data("not an mkv file at all".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!MatroskaHeaderReader.hasEBMLMagic(at: url))
        #expect(throws: MatroskaReadError.notMatroskaFile) {
            try MatroskaHeaderReader.readVideoHeader(at: url)
        }
    }
}
