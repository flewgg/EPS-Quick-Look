import CoreGraphics
import Foundation

struct EPSBoundingBox: Equatable {
    let rect: CGRect

    var size: CGSize {
        rect.size
    }
}

private enum EPSBoundingBoxComment {
    static let boundingBoxPrefix = "%%BoundingBox:"
    static let hiResBoundingBoxPrefix = "%%HiResBoundingBox:"
    static let endComments = "%%EndComments"
    static let trailer = "%%Trailer"
    static let atend = "(atend)"
}

private struct EPSBoundingBoxCandidates {
    private(set) var hiResBoundingBox: CGRect?
    private(set) var standardBoundingBox: CGRect?

    var preferredBoundingBox: EPSBoundingBox? {
        if let hiResBoundingBox {
            return EPSBoundingBox(rect: hiResBoundingBox)
        }

        if let standardBoundingBox {
            return EPSBoundingBox(rect: standardBoundingBox)
        }

        return nil
    }

    mutating func recordHiResBoundingBox(_ rect: CGRect?) {
        guard hiResBoundingBox == nil else {
            return
        }
        hiResBoundingBox = rect
    }

    mutating func recordStandardBoundingBox(_ rect: CGRect?) {
        guard standardBoundingBox == nil else {
            return
        }
        standardBoundingBox = rect
    }
}

enum EPSBoundingBoxParser {
    struct HeaderParseResult: Equatable {
        let boundingBox: EPSBoundingBox?
        let needsTrailerLookup: Bool
        let sawBoundingBoxComment: Bool
        let hasHiResBoundingBox: Bool
        let needsHiResTrailerLookup: Bool
    }

    static func boundingBox(for fileURL: URL) throws -> EPSBoundingBox? {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        let section = try postScriptSection(in: fileHandle, fileSize: fileSize)
        let sectionLength = section.upperBound - section.lowerBound
        try fileHandle.seek(toOffset: section.lowerBound)

        let headerLength = Int(min(sectionLength, 64 * 1024))
        let headerData = try fileHandle.read(upToCount: headerLength) ?? Data()

        let headerResult = parseHeaderBoundingBox(from: headerData)
        if let headerBoundingBox = headerResult.boundingBox,
           headerResult.hasHiResBoundingBox || !headerResult.needsHiResTrailerLookup {
            return headerBoundingBox
        }

        let shouldScanTrailer = headerResult.needsTrailerLookup || headerResult.sawBoundingBoxComment == false
        guard shouldScanTrailer else {
            return nil
        }

        let trailerLength = Int(min(sectionLength, 256 * 1024))
        let trailerOffset = section.upperBound - UInt64(trailerLength)
        try fileHandle.seek(toOffset: trailerOffset)
        let trailerData = try fileHandle.read(upToCount: trailerLength) ?? Data()

        let trailerCandidates = parseTrailerCandidates(from: trailerData)
        if headerResult.needsHiResTrailerLookup,
           let hiResBoundingBox = trailerCandidates.hiResBoundingBox {
            return EPSBoundingBox(rect: hiResBoundingBox)
        }
        return headerResult.boundingBox ?? trailerCandidates.preferredBoundingBox
    }

    private static func postScriptSection(in fileHandle: FileHandle, fileSize: UInt64) throws -> Range<UInt64> {
        try fileHandle.seek(toOffset: 0)
        let header = try fileHandle.read(upToCount: 30) ?? Data()
        guard header.starts(with: [0xC5, 0xD0, 0xD3, 0xC6]) else {
            return 0..<fileSize
        }
        guard header.count == 30 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        func unsignedValue(at offset: Int) -> UInt64 {
            header[offset..<(offset + 4)].enumerated().reduce(UInt64(0)) {
                $0 | UInt64($1.element) << ($1.offset * 8)
            }
        }

        let offset = unsignedValue(at: 4)
        let length = unsignedValue(at: 8)
        guard offset >= 30, length > 0, offset <= fileSize, length <= fileSize - offset else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return offset..<(offset + length)
    }

    static func parseHeaderBoundingBox(from data: Data) -> HeaderParseResult {
        let contents = String(decoding: data, as: UTF8.self)

        var sawBoundingBoxComment = false
        var needsStandardTrailerLookup = false
        var needsHiResTrailerLookup = false
        var candidates = EPSBoundingBoxCandidates()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == EPSBoundingBoxComment.endComments {
                break
            }

            if line.hasPrefix(EPSBoundingBoxComment.hiResBoundingBoxPrefix) {
                sawBoundingBoxComment = true
                if line.contains(EPSBoundingBoxComment.atend), candidates.hiResBoundingBox == nil {
                    needsHiResTrailerLookup = true
                } else if !needsHiResTrailerLookup {
                    candidates.recordHiResBoundingBox(
                        parseBoundingBoxRect(from: line, prefix: EPSBoundingBoxComment.hiResBoundingBoxPrefix)
                    )
                }
            }

            if line.hasPrefix(EPSBoundingBoxComment.boundingBoxPrefix) {
                sawBoundingBoxComment = true
                if line.contains(EPSBoundingBoxComment.atend), candidates.standardBoundingBox == nil {
                    needsStandardTrailerLookup = true
                } else if !needsStandardTrailerLookup {
                    candidates.recordStandardBoundingBox(
                        parseBoundingBoxRect(from: line, prefix: EPSBoundingBoxComment.boundingBoxPrefix)
                    )
                }
            }
        }

        return HeaderParseResult(
            boundingBox: candidates.preferredBoundingBox,
            needsTrailerLookup: needsStandardTrailerLookup || needsHiResTrailerLookup,
            sawBoundingBoxComment: sawBoundingBoxComment,
            hasHiResBoundingBox: candidates.hiResBoundingBox != nil,
            needsHiResTrailerLookup: needsHiResTrailerLookup
        )
    }

    static func parseTrailerBoundingBox(from data: Data) -> EPSBoundingBox? {
        parseTrailerCandidates(from: data).preferredBoundingBox
    }

    private static func parseTrailerCandidates(from data: Data) -> EPSBoundingBoxCandidates {
        let contents = String(decoding: data, as: UTF8.self)
        let lines = contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let trailerLines: ArraySlice<String>
        if let trailerIndex = lines.lastIndex(of: EPSBoundingBoxComment.trailer), trailerIndex + 1 < lines.endIndex {
            trailerLines = lines[(trailerIndex + 1)...]
        } else {
            trailerLines = lines[...]
        }

        var candidates = EPSBoundingBoxCandidates()

        for line in trailerLines.reversed() {
            if let parsed = parseBoundingBoxRect(from: line, prefix: EPSBoundingBoxComment.hiResBoundingBoxPrefix) {
                candidates.recordHiResBoundingBox(parsed)
            }

            if let parsed = parseBoundingBoxRect(from: line, prefix: EPSBoundingBoxComment.boundingBoxPrefix) {
                candidates.recordStandardBoundingBox(parsed)
            }

            if candidates.hiResBoundingBox != nil {
                break
            }
        }

        return candidates
    }

    static func parseBoundingBoxRect(from line: String, prefix: String) -> CGRect? {
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.contains(EPSBoundingBoxComment.atend) else {
            return nil
        }

        let components = value.split(whereSeparator: \.isWhitespace)
        guard components.count >= 4,
              let lowerLeftX = Double(components[0]),
              let lowerLeftY = Double(components[1]),
              let upperRightX = Double(components[2]),
              let upperRightY = Double(components[3]),
              lowerLeftX.isFinite,
              lowerLeftY.isFinite,
              upperRightX.isFinite,
              upperRightY.isFinite,
              upperRightX > lowerLeftX,
              upperRightY > lowerLeftY else {
            return nil
        }

        let width = upperRightX - lowerLeftX
        let height = upperRightY - lowerLeftY
        guard width.isFinite, height.isFinite else {
            return nil
        }

        return CGRect(
            x: lowerLeftX,
            y: lowerLeftY,
            width: width,
            height: height
        )
    }
}
