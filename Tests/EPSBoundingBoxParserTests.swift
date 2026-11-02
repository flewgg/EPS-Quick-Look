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

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EPSBoundingBoxParserTests-\(UUID().uuidString)")
            .appendingPathExtension("eps")
    }
}
