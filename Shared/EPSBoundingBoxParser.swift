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
    }

    static func boundingBox(for fileURL: URL) throws -> EPSBoundingBox? {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        let headerLength = Int(min(fileSize, 64 * 1024))
        let headerData = try fileHandle.read(upToCount: headerLength) ?? Data()

        let headerResult = parseHeaderBoundingBox(from: headerData)
        if let headerBoundingBox = headerResult.boundingBox {
            return headerBoundingBox
        }

        let shouldScanTrailer = headerResult.needsTrailerLookup || headerResult.sawBoundingBoxComment == false
        guard shouldScanTrailer else {
            return nil
        }

        let trailerLength = Int(min(fileSize, 256 * 1024))
        let trailerOffset = fileSize > UInt64(trailerLength) ? fileSize - UInt64(trailerLength) : 0
        try fileHandle.seek(toOffset: trailerOffset)
        let trailerData = try fileHandle.readToEnd() ?? Data()

        return parseTrailerBoundingBox(from: trailerData)
    }

    static func parseHeaderBoundingBox(from data: Data) -> HeaderParseResult {
        let contents = String(decoding: data, as: UTF8.self)

        var sawBoundingBoxComment = false
        var needsTrailerLookup = false
        var candidates = EPSBoundingBoxCandidates()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == EPSBoundingBoxComment.endComments {
                break
            }

            if line.hasPrefix(EPSBoundingBoxComment.hiResBoundingBoxPrefix) {
                sawBoundingBoxComment = true
                if line.contains(EPSBoundingBoxComment.atend) {
                    needsTrailerLookup = true
                } else {
                    candidates.recordHiResBoundingBox(
                        parseBoundingBoxRect(from: line, prefix: EPSBoundingBoxComment.hiResBoundingBoxPrefix)
                    )
                }
            }

            if line.hasPrefix(EPSBoundingBoxComment.boundingBoxPrefix) {
                sawBoundingBoxComment = true
                if line.contains(EPSBoundingBoxComment.atend) {
                    needsTrailerLookup = true
                } else {
                    candidates.recordStandardBoundingBox(
                        parseBoundingBoxRect(from: line, prefix: EPSBoundingBoxComment.boundingBoxPrefix)
                    )
                }
            }
        }

        return HeaderParseResult(
            boundingBox: candidates.preferredBoundingBox,
            needsTrailerLookup: needsTrailerLookup,
            sawBoundingBoxComment: sawBoundingBoxComment
        )
    }

    static func parseTrailerBoundingBox(from data: Data) -> EPSBoundingBox? {
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

        return candidates.preferredBoundingBox
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
              upperRightX > lowerLeftX,
              upperRightY > lowerLeftY else {
            return nil
        }

        return CGRect(
            x: lowerLeftX,
            y: lowerLeftY,
            width: max(upperRightX - lowerLeftX, 1),
            height: max(upperRightY - lowerLeftY, 1)
        )
    }
}
