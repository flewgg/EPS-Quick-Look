import CoreGraphics
import Foundation
import XCTest

final class EPSBoundingBoxParserTests: XCTestCase {
    func testHeaderParserPrefersHiResBoundingBoxOverStandardBoundingBox() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 0 0 100 200
        %%HiResBoundingBox: 1.5 2.25 301.75 402.5
        %%EndComments
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertEqual(result.boundingBox?.rect, CGRect(x: 1.5, y: 2.25, width: 300.25, height: 400.25))
        XCTAssertFalse(result.needsTrailerLookup)
        XCTAssertTrue(result.sawBoundingBoxComment)
    }

    func testHeaderParserFallsBackToStandardBoundingBox() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 10 20 210 420
        %%EndComments
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertEqual(result.boundingBox?.rect, CGRect(x: 10, y: 20, width: 200, height: 400))
        XCTAssertFalse(result.needsTrailerLookup)
        XCTAssertTrue(result.sawBoundingBoxComment)
    }

    func testHeaderParserMarksAtendBoundingBoxForTrailerLookup() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: (atend)
        %%EndComments
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertNil(result.boundingBox)
        XCTAssertTrue(result.needsTrailerLookup)
        XCTAssertTrue(result.sawBoundingBoxComment)
    }

    func testHeaderParserIgnoresBoundingBoxesAfterEndComments() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%EndComments
        %%BoundingBox: 10 20 210 420
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertNil(result.boundingBox)
        XCTAssertFalse(result.needsTrailerLookup)
        XCTAssertFalse(result.sawBoundingBoxComment)
    }

    func testHeaderParserUsesFirstBoundingBox() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 100 150 300 450
        %%BoundingBox: 10 20 400 500
        %%EndComments
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertEqual(result.boundingBox?.rect, CGRect(x: 100, y: 150, width: 200, height: 300))
    }

    func testHeaderParserUsesFirstHiResBoundingBox() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%HiResBoundingBox: 100.5 150.5 299.5 449.5
        %%HiResBoundingBox: 20 30 420 530
        %%EndComments
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertEqual(result.boundingBox?.rect, CGRect(x: 100.5, y: 150.5, width: 199, height: 299))
    }

    func testTrailerParserUsesLastHiResBoundingBoxAfterTrailerMarker() throws {
        let data = data("""
        %%BoundingBox: 0 0 10 10
        %%Trailer
        %%BoundingBox: 10 20 210 420
        %%HiResBoundingBox: 1.25 2.5 301.75 402.25
        """)

        let boundingBox = EPSBoundingBoxParser.parseTrailerBoundingBox(from: data)

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 1.25, y: 2.5, width: 300.5, height: 399.75))
    }

    func testTrailerParserPrefersHiResBoundingBoxOverLaterStandardBoundingBox() throws {
        let data = data("""
        %%Trailer
        %%HiResBoundingBox: 1.25 2.5 301.75 402.25
        %%BoundingBox: 10 20 210 420
        """)

        let boundingBox = EPSBoundingBoxParser.parseTrailerBoundingBox(from: data)

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 1.25, y: 2.5, width: 300.5, height: 399.75))
    }

    func testHeaderParserKeepsEarlierValidBoundingBoxWhenLaterLineIsInvalid() throws {
        let data = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 10 20 210 420
        %%BoundingBox: nope 0 10 10
        %%EndComments
        """)

        let result = EPSBoundingBoxParser.parseHeaderBoundingBox(from: data)

        XCTAssertEqual(result.boundingBox?.rect, CGRect(x: 10, y: 20, width: 200, height: 400))
        XCTAssertFalse(result.needsTrailerLookup)
        XCTAssertTrue(result.sawBoundingBoxComment)
    }

    func testFileParserFindsTrailerBoundingBoxWhenHeaderUsesAtend() throws {
        let fileURL = temporaryFileURL()
        try data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: (atend)
        %%EndComments
        /Helvetica findfont 12 scalefont setfont
        %%Trailer
        %%BoundingBox: 10 20 210 420
        """).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let boundingBox = try EPSBoundingBoxParser.boundingBox(for: fileURL)

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 10, y: 20, width: 200, height: 400))
    }

    func testBoundingBoxRectRejectsInvalidOrInvertedValues() throws {
        XCTAssertNil(EPSBoundingBoxParser.parseBoundingBoxRect(from: "%%BoundingBox: (atend)", prefix: "%%BoundingBox:"))
        XCTAssertNil(EPSBoundingBoxParser.parseBoundingBoxRect(from: "%%BoundingBox: 0 0 0 10", prefix: "%%BoundingBox:"))
        XCTAssertNil(EPSBoundingBoxParser.parseBoundingBoxRect(from: "%%BoundingBox: 0 10 10 0", prefix: "%%BoundingBox:"))
        XCTAssertNil(EPSBoundingBoxParser.parseBoundingBoxRect(from: "%%BoundingBox: nope 0 10 10", prefix: "%%BoundingBox:"))
    }

    func testBoundingBoxRectRejectsNonfiniteCoordinatesAndOverflowingDimensions() {
        for values in [
            "0 0 inf 100",
            "-inf 0 100 100",
            "0 -inf 100 100",
            "0 0 100 inf",
            "nan 0 100 100",
            "-1e308 0 1e308 100",
            "0 -1e308 100 1e308",
        ] {
            XCTAssertNil(EPSBoundingBoxParser.parseBoundingBoxRect(from: "%%BoundingBox: \(values)", prefix: "%%BoundingBox:"), values)
        }
    }

    func testBoundingBoxRectPreservesSubpointDimensions() {
        let rect = EPSBoundingBoxParser.parseBoundingBoxRect(
            from: "%%HiResBoundingBox: -0.125 0.25 0.125 0.75",
            prefix: "%%HiResBoundingBox:"
        )

        XCTAssertEqual(rect, CGRect(x: -0.125, y: 0.25, width: 0.25, height: 0.5))
    }

    func testFileParserReadsDeferredHiResBoxWhenStandardHeaderBoxIsAvailable() throws {
        let boundingBox = try parseFile(data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 99 99 201 201
        %%HiResBoundingBox: (atend)
        %%EndComments
        showpage
        %%Trailer
        %%HiResBoundingBox: 100.25 100.25 199.75 199.75
        """))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 100.25, y: 100.25, width: 99.5, height: 99.5))
    }

    func testFileParserKeepsHeaderHiResBoxWhenStandardBoxIsDeferred() throws {
        let boundingBox = try parseFile(data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: (atend)
        %%HiResBoundingBox: 100.25 100.25 199.75 199.75
        %%EndComments
        showpage
        %%Trailer
        %%BoundingBox: 99 99 201 201
        %%HiResBoundingBox: 0 0 10 10
        """))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 100.25, y: 100.25, width: 99.5, height: 99.5))
    }

    func testFileParserFallsBackToHeaderStandardBoxWhenDeferredHiResBoxIsMissing() throws {
        let boundingBox = try parseFile(data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 99 99 201 201
        %%HiResBoundingBox: (atend)
        %%EndComments
        showpage
        %%Trailer
        %%BoundingBox: 0 0 10 10
        """))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 99, y: 99, width: 102, height: 102))
    }

    func testFileParserKeepsFirstDeferredHeaderDeclarations() throws {
        let boundingBox = try parseFile(data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: (atend)
        %%HiResBoundingBox: (atend)
        %%BoundingBox: 0 0 10 10
        %%HiResBoundingBox: 0 0 10 10
        %%EndComments
        showpage
        %%Trailer
        %%BoundingBox: 99 99 201 201
        %%HiResBoundingBox: 100.25 100.25 199.75 199.75
        """))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 100.25, y: 100.25, width: 99.5, height: 99.5))
    }

    func testFileParserIgnoresBoundingBoxesInDOSPreviewBeforePostScript() throws {
        let postScript = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: 100 150 300 450
        %%EndComments
        showpage
        """)
        let preview = data("\n%%BoundingBox: 0 0 10 10\n%%EndComments\n")

        let boundingBox = try parseFile(dosEPS(postScript: postScript, preview: preview, previewFirst: true))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 100, y: 150, width: 200, height: 300))
    }

    func testFileParserFindsDOSHeaderBeyondPreviewWithLargePostScriptBody() throws {
        let postScript = data("%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: -100 -150 100 150\n%%EndComments\n%")
            + Data(repeating: 120, count: 300_000)
            + data("\nshowpage\n%%EOF\n")

        let boundingBox = try parseFile(dosEPS(
            postScript: postScript,
            preview: Data(repeating: 0, count: 100_000),
            previewFirst: true
        ))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: -100, y: -150, width: 200, height: 300))
    }

    func testFileParserBoundsTrailerLookupToDOSPostScriptSection() throws {
        let postScript = data("""
        %!PS-Adobe-3.0 EPSF-3.0
        %%BoundingBox: (atend)
        %%EndComments
        showpage
        %%Trailer
        %%BoundingBox: 100 150 300 450
        %%EOF
        """)
        let preview = data("\n%%Trailer\n%%HiResBoundingBox: 0 0 10 10\n")

        let boundingBox = try parseFile(dosEPS(postScript: postScript, preview: preview, previewFirst: false))

        XCTAssertEqual(boundingBox?.rect, CGRect(x: 100, y: 150, width: 200, height: 300))
    }

    func testFileParserRejectsInvalidDOSPostScriptRanges() throws {
        let postScript = data("%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 100 100\n")
        let validDocument = dosEPS(postScript: postScript, preview: Data(), previewFirst: false)
        XCTAssertThrowsError(try parseFile(validDocument.prefix(12)))

        for (offset, length) in [(UInt32(0), UInt32(10)), (30, 0), (UInt32.max, 10), (30, UInt32.max)] {
            var document = validDocument
            var invalidOffset = offset.littleEndian
            var invalidLength = length.littleEndian
            withUnsafeBytes(of: &invalidOffset) { document.replaceSubrange(4..<8, with: $0) }
            withUnsafeBytes(of: &invalidLength) { document.replaceSubrange(8..<12, with: $0) }
            XCTAssertThrowsError(try parseFile(document), "offset \(offset), length \(length)")
        }
    }

    private func parseFile(_ contents: Data) throws -> EPSBoundingBox? {
        let fileURL = temporaryFileURL()
        try contents.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        return try EPSBoundingBoxParser.boundingBox(for: fileURL)
    }

    private func dosEPS(postScript: Data, preview: Data, previewFirst: Bool) -> Data {
        let headerLength = 30
        let postScriptOffset = previewFirst ? headerLength + preview.count : headerLength
        let previewOffset = previewFirst ? headerLength : headerLength + postScript.count
        var document = Data([0xC5, 0xD0, 0xD3, 0xC6])
        for field in [postScriptOffset, postScript.count, 0, 0, previewOffset, preview.count] {
            withUnsafeBytes(of: UInt32(field).littleEndian) { document.append(contentsOf: $0) }
        }
        document.append(contentsOf: [0xFF, 0xFF])
        document.append(previewFirst ? preview : postScript)
        document.append(previewFirst ? postScript : preview)
        return document
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EPSBoundingBoxParserTests-\(UUID().uuidString)")
            .appendingPathExtension("eps")
    }
}
