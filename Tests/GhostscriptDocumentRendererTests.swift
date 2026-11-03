import CoreGraphics
import Foundation
import PDFKit
import XCTest

final class GhostscriptDocumentRendererTests: XCTestCase {
    private struct Sample {
        let name: String
        let contents: Data
        let expectedSize: CGSize
    }

    func testBoundingBoxAwayFromOriginFromIssue1() throws {
        try assertArtFillsPage(Sample(
            name: "Illustrator 8 box",
            contents: eps(
                comments: [
                    "%%BoundingBox: 171 209 397 589",
                    "%%HiResBoundingBox: 171.4399 209.7217 396.4199 588.7744",
                ],
                art: CGRect(x: 171.4399, y: 209.7217, width: 224.98, height: 379.0527)
            ),
            expectedSize: CGSize(width: 224.98, height: 379.0527)
        ))
    }

    func testOldFilesFromIssue2() throws {
        let corelBox = CGRect(x: 2079, y: 2171, width: 508, height: 360)
        let plainBox = CGRect(x: 100, y: 150, width: 200, height: 300)
        let plainDocument = eps(firstLine: "%!PS-Adobe-2.0 EPSF-2.0", comments: ["%%BoundingBox: 100 150 300 450"], art: plainBox)

        try [
            Sample(
                name: "CorelDRAW box far from the origin with CRLF line endings",
                contents: eps(
                    firstLine: "%!PS-Adobe-2.0 EPSF-2.0",
                    comments: ["%%BoundingBox: 2079 2171 2587 2531 "],
                    art: corelBox,
                    lineEnding: "\r\n"
                ),
                expectedSize: corelBox.size
            ),
            Sample(
                name: "MATLAB style EPSF-1.2 header",
                contents: eps(
                    firstLine: "%!PS-Adobe-2.0 EPSF-1.2",
                    comments: ["%%BoundingBox: 58 204 566 605"],
                    art: CGRect(x: 58, y: 204, width: 508, height: 401)
                ),
                expectedSize: CGSize(width: 508, height: 401)
            ),
            Sample(
                name: "CR line endings",
                contents: eps(
                    firstLine: "%!PS-Adobe-2.0 EPSF-2.0",
                    comments: ["%%BoundingBox: 100 150 300 450"],
                    art: plainBox,
                    lineEnding: "\r"
                ),
                expectedSize: plainBox.size
            ),
            Sample(
                name: "Latin-1 bytes in the header",
                contents: Data("%!PS-Adobe-2.0 EPSF-2.0\n%%Title: ".utf8) + Data([0x65, 0x74, 0xE9]) + Data("\n".utf8)
                    + eps(firstLine: "%%Creator: test", comments: ["%%BoundingBox: 100 150 300 450"], art: plainBox),
                expectedSize: plainBox.size
            ),
            Sample(
                name: "No showpage",
                contents: eps(
                    firstLine: "%!PS-Adobe-2.0 EPSF-2.0",
                    comments: ["%%BoundingBox: 100 150 300 450"],
                    art: plainBox,
                    showpage: false
                ),
                expectedSize: plainBox.size
            ),
            Sample(
                name: "Binary DOS header with the preview after the PostScript",
                contents: dosEPS(postScript: plainDocument, preview: previewBytes(count: 2048), previewFirst: false),
                expectedSize: plainBox.size
            ),
            Sample(
                name: "Binary DOS header with a large preview before the PostScript",
                contents: dosEPS(postScript: plainDocument, preview: previewBytes(count: 102_400), previewFirst: true),
                expectedSize: plainBox.size
            ),
        ].forEach(assertArtFillsPage)
    }

    func testBoundingBoxesGhostscriptIgnores() throws {
        try [
            Sample(
                name: "(atend) box away from the origin",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: 100, y: 150, width: 200, height: 300),
                    trailer: ["%%BoundingBox: 100 150 300 450"]
                ),
                expectedSize: CGSize(width: 200, height: 300)
            ),
            Sample(
                name: "Non-EPSF header away from the origin",
                contents: eps(
                    firstLine: "%!PS-Adobe-3.0",
                    comments: ["%%BoundingBox: 100 150 300 450"],
                    art: CGRect(x: 100, y: 150, width: 200, height: 300)
                ),
                expectedSize: CGSize(width: 200, height: 300)
            ),
            Sample(
                name: "(atend) box larger than a letter page",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: 0, y: 0, width: 2000, height: 2000),
                    trailer: ["%%BoundingBox: 0 0 2000 2000"]
                ),
                expectedSize: CGSize(width: 2000, height: 2000)
            ),
            Sample(
                name: "(atend) box the size of a letter page away from the origin",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: 10, y: 20, width: 612, height: 792),
                    trailer: ["%%BoundingBox: 10 20 622 812"]
                ),
                expectedSize: CGSize(width: 612, height: 792)
            ),
        ].forEach(assertArtFillsPage)
    }

    func testNegativeOrigins() throws {
        let art = CGRect(x: -50, y: -80, width: 200, height: 300)

        try [
            Sample(
                name: "EPSF header",
                contents: eps(comments: ["%%BoundingBox: -50 -80 150 220"], art: art),
                expectedSize: art.size
            ),
            Sample(
                name: "(atend) box",
                contents: eps(comments: ["%%BoundingBox: (atend)"], art: art, trailer: ["%%BoundingBox: -50 -80 150 220"]),
                expectedSize: art.size
            ),
            Sample(
                name: "Non-EPSF header",
                contents: eps(firstLine: "%!PS-Adobe-3.0", comments: ["%%BoundingBox: -50 -80 150 220"], art: art),
                expectedSize: art.size
            ),
            Sample(
                name: "Only x negative",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: -50, y: 100, width: 200, height: 300),
                    trailer: ["%%BoundingBox: -50 100 150 400"]
                ),
                expectedSize: art.size
            ),
            Sample(
                name: "Only y negative with x at zero",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: 0, y: -80, width: 200, height: 300),
                    trailer: ["%%BoundingBox: 0 -80 200 220"]
                ),
                expectedSize: art.size
            ),
            Sample(
                name: "Entirely below zero",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: -300, y: -400, width: 200, height: 300),
                    trailer: ["%%BoundingBox: -300 -400 -100 -100"]
                ),
                expectedSize: art.size
            ),
            Sample(
                name: "Fractional size",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)", "%%HiResBoundingBox: (atend)"],
                    art: CGRect(x: -50.5, y: -80.25, width: 200.25, height: 300.15),
                    trailer: ["%%HiResBoundingBox: -50.5 -80.25 149.75 219.9"]
                ),
                expectedSize: CGSize(width: 200.25, height: 300.15)
            ),
            Sample(
                name: "Wider than 14400pt",
                contents: eps(
                    comments: ["%%BoundingBox: (atend)"],
                    art: CGRect(x: -100, y: -100, width: 20100, height: 300),
                    trailer: ["%%BoundingBox: -100 -100 20000 200"]
                ),
                expectedSize: CGSize(width: 20100, height: 300)
            ),
            Sample(
                name: "File that sets its own page size",
                contents: eps(comments: ["%%BoundingBox: -50 -80 150 220"], setup: ["<</PageSize [612 792]>> setpagedevice"], art: art),
                expectedSize: art.size
            ),
        ].forEach(assertArtFillsPage)
    }

    func testPositiveOriginsUseFixedBoundingBoxMedia() throws {
        let samples: [(String, CGRect, [String])] = [
            ("File that sets a smaller page size", CGRect(x: 100, y: 200, width: 2400, height: 1200), ["<</PageSize [612 792]>> setpagedevice"]),
            ("Origin beyond 14400pt", CGRect(x: 15000, y: 15000, width: 240, height: 120), []),
            ("Artwork beyond 14400pt", CGRect(x: 100, y: 200, width: 18000, height: 9000), []),
        ]

        for (name, art, setup) in samples {
            for firstLine in ["%!PS-Adobe-3.0", "%!PS-Adobe-3.0 EPSF-3.0"] {
                try assertArtFillsPage(Sample(
                    name: "\(name), \(firstLine)",
                    contents: eps(
                        firstLine: firstLine,
                        comments: ["%%BoundingBox: \(art.minX) \(art.minY) \(art.maxX) \(art.maxY)"],
                        setup: setup,
                        art: art
                    ),
                    expectedSize: art.size
                ))
            }
        }
    }

    func testPostScriptWithoutBoundingBoxKeepsItsPageSize() throws {
        let art = CGRect(x: 0, y: 0, width: 240, height: 120)
        try assertArtFillsPage(Sample(
            name: "PostScript without a bounding box",
            contents: eps(
                firstLine: "%!PS-Adobe-3.0",
                comments: [],
                setup: ["<</PageSize [240 120]>> setpagedevice"],
                art: art
            ),
            expectedSize: art.size
        ))
    }

    func testBinaryPreviewCannotOverridePostScriptBoundingBox() throws {
        let art = CGRect(x: 100, y: 150, width: 200, height: 300)
        let postScript = eps(
            firstLine: "%!PS-Adobe-3.0",
            comments: ["%%BoundingBox: 100 150 300 450"],
            art: art
        )
        let preview = Data("\n%%BoundingBox: 0 0 10 10\n%%EndComments\n".utf8) + previewBytes(count: 102_400)

        try assertArtFillsPage(Sample(
            name: "Bounding box text in a binary preview",
            contents: dosEPS(postScript: postScript, preview: preview, previewFirst: true),
            expectedSize: art.size
        ))
    }

    func testDeferredHiResBoundingBoxOverridesHeaderStandardBox() throws {
        let art = CGRect(x: 100.2, y: 100.2, width: 99.6, height: 99.6)
        try assertArtFillsPage(Sample(
            name: "Deferred high-resolution bounds",
            contents: eps(
                comments: ["%%BoundingBox: 99 99 201 201", "%%HiResBoundingBox: (atend)"],
                art: art,
                trailer: ["%%HiResBoundingBox: 100.2 100.2 199.8 199.8"]
            ),
            expectedSize: art.size
        ))
    }

    func testSubpointArtworkKeepsItsExactSize() throws {
        let art = CGRect(x: 0, y: 0, width: 0.25, height: 0.5)
        try assertArtFillsPage(Sample(
            name: "Subpoint artwork",
            contents: eps(comments: ["%%BoundingBox: 0 0 1 1", "%%HiResBoundingBox: 0 0 0.25 0.5"], art: art),
            expectedSize: art.size
        ))
    }

    func testColoredArtworkPreservesItsPositionAndOrientation() throws {
        for firstLine in ["%!PS-Adobe-3.0", "%!PS-Adobe-3.0 EPSF-3.0"] {
            for origin in [CGPoint(x: 100, y: 200), CGPoint(x: -100, y: -60)] {
                let fileURL = try write(Data("""
                \(firstLine)
                %%BoundingBox: \(origin.x) \(origin.y) \(origin.x + 240) \(origin.y + 120)
                %%EndComments
                <</PageSize [612 792]>> setpagedevice
                1 0 0 setrgbcolor \(origin.x) \(origin.y) 120 60 rectfill
                0 1 0 setrgbcolor \(origin.x + 120) \(origin.y) 120 60 rectfill
                0 0 1 setrgbcolor \(origin.x) \(origin.y + 60) 120 60 rectfill
                1 0 1 setrgbcolor \(origin.x + 120) \(origin.y + 60) 120 60 rectfill
                showpage
                """.utf8))
                let preview = try GhostscriptDocumentRenderer().renderPDFPreview(for: fileURL)
                removeAfterTest(preview.url.deletingLastPathComponent())
                let document = try XCTUnwrap(CGPDFDocument(preview.url as CFURL))
                let page = try XCTUnwrap(document.page(at: 1))
                let context = try XCTUnwrap(CGContext(
                    data: nil,
                    width: 240,
                    height: 120,
                    bitsPerComponent: 8,
                    bytesPerRow: 240 * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.drawPDFPage(page)
                let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 240 * 120 * 4)
                let samples: [(Int, Int, [UInt8])] = [
                    (60, 30, [0, 0, 255]),
                    (180, 30, [255, 0, 255]),
                    (60, 90, [255, 0, 0]),
                    (180, 90, [0, 255, 0]),
                ]
                for (x, y, expected) in samples {
                    let offset = (y * 240 + x) * 4
                    for channel in 0..<3 {
                        XCTAssertLessThanOrEqual(abs(Int(pixels[offset + channel]) - Int(expected[channel])), 2, "\(firstLine), \(origin), pixel \(x),\(y), channel \(channel)")
                    }
                }
            }
        }
    }

    func testPageDeviceChangesKeepBoundingBoxPlacement() throws {
        for setup in [
            "<</PageOffset [0 0]>> setpagedevice",
            "[ /CropBox [10 10 230 110] /PAGES pdfmark",
            "[ /CropBox [100 200 340 320] /PAGES pdfmark",
        ] {
            for origin in [CGPoint(x: 100, y: 200), CGPoint(x: -100, y: -60)] {
                let art = CGRect(origin: origin, size: CGSize(width: 240, height: 120))
                try assertArtFillsPage(Sample(
                    name: "\(setup), \(origin)",
                    contents: eps(
                        comments: ["%%BoundingBox: \(art.minX) \(art.minY) \(art.maxX) \(art.maxY)"],
                        setup: [setup],
                        art: art
                    ),
                    expectedSize: art.size
                ))
            }
        }
    }

    func testFirstBoundingBoxInHeaderIsUsed() throws {
        let art = CGRect(x: 100, y: 150, width: 200, height: 300)

        try [
            Sample(
                name: "Two standard boxes",
                contents: eps(comments: ["%%BoundingBox: 100 150 300 450", "%%BoundingBox: 10 20 400 500"], art: art),
                expectedSize: art.size
            ),
            Sample(
                name: "Two HiRes boxes",
                contents: eps(
                    comments: [
                        "%%BoundingBox: 100 150 300 450",
                        "%%HiResBoundingBox: 100 150 300 450",
                        "%%HiResBoundingBox: 20 30 420 530",
                    ],
                    art: art
                ),
                expectedSize: art.size
            ),
        ].forEach(assertArtFillsPage)
    }

    func testThumbnailPageMatchesBoundingBox() throws {
        let fileURL = try write(eps(
            firstLine: "%!PS-Adobe-2.0 EPSF-2.0",
            comments: ["%%BoundingBox: 2079 2171 2587 2531"],
            art: CGRect(x: 2079, y: 2171, width: 508, height: 360)
        ))

        let renderedPage = try GhostscriptDocumentRenderer().renderFirstPage(for: fileURL)
        removeAfterTest(renderedPage.document.documentURL?.deletingLastPathComponent())

        XCTAssertEqual(renderedPage.pageRect.origin, .zero)
        XCTAssertEqual(renderedPage.pageRect.width, 508, accuracy: 0.5)
        XCTAssertEqual(renderedPage.pageRect.height, 360, accuracy: 0.5)
    }

    private func assertArtFillsPage(_ sample: Sample) throws {
        let fileURL = try write(sample.contents)

        let preview = try GhostscriptDocumentRenderer().renderPDFPreview(for: fileURL)
        removeAfterTest(preview.url.deletingLastPathComponent())

        XCTAssertEqual(preview.contentSize.width, sample.expectedSize.width, accuracy: 0.01, sample.name)
        XCTAssertEqual(preview.contentSize.height, sample.expectedSize.height, accuracy: 0.01, sample.name)
        XCTAssertGreaterThan(try inkCoverage(ofPDFAt: preview.url), 0.99, sample.name)
    }

    private func inkCoverage(ofPDFAt url: URL) throws -> Double {
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let scale = 1000 / max(box.width, box.height)
        let width = Int((box.width * scale).rounded(.up))
        let height = Int((box.height * scale).rounded(.up))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)

        let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let inkedPixels = (0..<(width * height)).reduce(0) { $0 + (pixels[$1 * 4] < 128 ? 1 : 0) }
        return Double(inkedPixels) / Double(width * height)
    }

    private func eps(
        firstLine: String = "%!PS-Adobe-3.0 EPSF-3.0",
        comments: [String],
        setup: [String] = [],
        art: CGRect,
        trailer: [String] = [],
        lineEnding: String = "\n",
        showpage: Bool = true
    ) -> Data {
        var lines = [firstLine] + comments + ["%%EndComments"] + setup
        lines.append("0 setgray \(art.minX) \(art.minY) \(art.width) \(art.height) rectfill")
        if showpage {
            lines.append("showpage")
        }
        if !trailer.isEmpty {
            lines += ["%%Trailer"] + trailer
        }
        lines.append("%%EOF")
        return Data((lines.joined(separator: lineEnding) + lineEnding).utf8)
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

    private func previewBytes(count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
    }

    private func write(_ contents: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GhostscriptDocumentRendererTests-\(UUID().uuidString)")
            .appendingPathExtension("eps")
        try contents.write(to: fileURL)
        removeAfterTest(fileURL)
        return fileURL
    }

    private func removeAfterTest(_ url: URL?) {
        guard let url else {
            return
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
