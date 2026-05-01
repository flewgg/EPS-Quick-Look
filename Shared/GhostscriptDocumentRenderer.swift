import CoreGraphics
import Foundation
import PDFKit

private typealias gsapi_new_instance_fn = @convention(c) (UnsafeMutablePointer<OpaquePointer?>, OpaquePointer?) -> Int32
private typealias gsapi_delete_instance_fn = @convention(c) (OpaquePointer) -> Void
private typealias gsapi_init_with_args_fn = @convention(c) (OpaquePointer, Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
private typealias gsapi_exit_fn = @convention(c) (OpaquePointer) -> Int32

struct RenderedPDFPreview {
    let url: URL
    let contentSize: CGSize
}

struct RenderedPDFPage {
    let document: PDFDocument
    let page: PDFPage
    let displayBox: PDFDisplayBox
    let pageRect: CGRect
}

private final class GhostscriptResourceLocator: NSObject {}

private struct NormalizedPDFOutput {
    let url: URL
    let contentSize: CGSize
}

private enum PDFNormalizationStrategy {
    case pdfDisplayBox(displayBox: PDFDisplayBox, rect: CGRect)
    case epsBoundingBox(EPSBoundingBox)

    var contentSize: CGSize {
        switch self {
        case let .pdfDisplayBox(_, rect):
            return rect.size
        case let .epsBoundingBox(boundingBox):
            return boundingBox.size
        }
    }
}

private enum GhostscriptRenderingError: LocalizedError, CustomNSError {
    case failedToLoadLibrary(String)
    case missingSymbol(String)
    case invalidRenderedPageSize
    case missingRenderedPage
    case failedToCreateInstance(Int32)
    case ghostscriptFailed(Int32)
    case missingBundledParser
    case missingContentSize
    case missingPageReference
    case failedToCreateNormalizedPDF

    static var errorDomain: String {
        "EPSQuickLook.Ghostscript"
    }

    var errorCode: Int {
        switch self {
        case .failedToLoadLibrary:
            return 1
        case .missingSymbol:
            return 2
        case .missingRenderedPage:
            return 3
        case .invalidRenderedPageSize:
            return 4
        case let .failedToCreateInstance(code):
            return Int(code)
        case .missingBundledParser:
            return 5
        case .missingContentSize:
            return 6
        case .missingPageReference:
            return 7
        case .failedToCreateNormalizedPDF:
            return 8
        case let .ghostscriptFailed(code):
            return Int(code)
        }
    }

    var errorDescription: String? {
        switch self {
        case let .failedToLoadLibrary(error):
            return "Failed to load Ghostscript library: \(error)"
        case let .missingSymbol(symbol):
            return "Missing Ghostscript symbol: \(symbol)"
        case .invalidRenderedPageSize:
            return "The rendered PDF page has an invalid size."
        case .missingRenderedPage:
            return "Ghostscript rendered a PDF thumbnail, but no PDF page was available."
        case .failedToCreateInstance:
            return "Failed to create Ghostscript instance."
        case let .ghostscriptFailed(code):
            return "Ghostscript failed with code \(code)."
        case .missingBundledParser:
            return "The bundled Ghostscript parser could not be found."
        case .missingContentSize:
            return "Ghostscript rendered a PDF preview, but its size could not be determined."
        case .missingPageReference:
            return "The rendered PDF preview page could not be normalized."
        case .failedToCreateNormalizedPDF:
            return "The normalized PDF preview could not be created."
        }
    }
}

private struct GhostscriptLibrary {
    let handle: UnsafeMutableRawPointer
    let newInstance: gsapi_new_instance_fn
    let deleteInstance: gsapi_delete_instance_fn
    let initWithArgs: gsapi_init_with_args_fn
    let exit: gsapi_exit_fn

    init(parserPath: String) throws {
        guard let handle = dlopen(parserPath, RTLD_LAZY) else {
            let error = String(cString: dlerror())
            throw GhostscriptRenderingError.failedToLoadLibrary(error)
        }
        self.handle = handle

        func resolve<T>(_ symbol: String) throws -> T {
            guard let resolved = dlsym(handle, symbol) else {
                throw GhostscriptRenderingError.missingSymbol(symbol)
            }
            return unsafeBitCast(resolved, to: T.self)
        }

        newInstance = try resolve("gsapi_new_instance")
        deleteInstance = try resolve("gsapi_delete_instance")
        initWithArgs = try resolve("gsapi_init_with_args")
        exit = try resolve("gsapi_exit")
    }
}

final class GhostscriptDocumentRenderer {
    func renderPDFPreview(for fileURL: URL) throws -> RenderedPDFPreview {
        let normalizedOutput = try renderNormalizedFirstPage(for: fileURL)
        return RenderedPDFPreview(url: normalizedOutput.url, contentSize: normalizedOutput.contentSize)
    }

    func renderFirstPage(for fileURL: URL) throws -> RenderedPDFPage {
        let normalizedOutput = try renderNormalizedFirstPage(for: fileURL)

        let (document, page) = try loadFirstPage(from: normalizedOutput.url)

        let (displayBox, pageRect) = preferredDisplayBox(for: page)
        guard pageRect.width > 0, pageRect.height > 0 else {
            throw GhostscriptRenderingError.invalidRenderedPageSize
        }

        return RenderedPDFPage(document: document, page: page, displayBox: displayBox, pageRect: pageRect)
    }

    private func renderNormalizedFirstPage(for fileURL: URL) throws -> NormalizedPDFOutput {
        let sourceBoundingBox = try EPSBoundingBoxParser.boundingBox(for: fileURL)
        let outputURL = try renderPDF(for: fileURL)
        return try normalizedFirstPageOutput(
            from: outputURL,
            fallbackFileURL: fileURL,
            sourceBoundingBox: sourceBoundingBox
        )
    }

    private func loadFirstPage(from outputURL: URL) throws -> (PDFDocument, PDFPage) {
        guard let document = PDFDocument(url: outputURL),
              let page = document.page(at: 0) else {
            throw GhostscriptRenderingError.missingRenderedPage
        }

        return (document, page)
    }

    private func renderPDF(for fileURL: URL) throws -> URL {
        let parserPath = try parserExecutablePath()

        let ghostscript = try GhostscriptLibrary(parserPath: parserPath)
        defer { dlclose(ghostscript.handle) }

        let temporaryDirectory = try PreviewTemporaryStorage.makeManagedTemporaryDirectory(prefix: "Preview")
        let outputURL = temporaryDirectory
            .appendingPathComponent("rendered")
            .appendingPathExtension("pdf")

        var instance: OpaquePointer?
        let newInstanceResult = ghostscript.newInstance(&instance, nil)
        guard newInstanceResult == 0, let ghostscriptInstance = instance else {
            throw GhostscriptRenderingError.failedToCreateInstance(newInstanceResult)
        }

        defer {
            _ = ghostscript.exit(ghostscriptInstance)
            ghostscript.deleteInstance(ghostscriptInstance)
        }

        let arguments = [
            "gs",
            "-dSAFER",
            "-dBATCH",
            "-dNOPAUSE",
            "-dNOPROMPT",
            "-sOutputFile=\(outputURL.path)",
            "-dEPSCrop",
            "-dFirstPage=1",
            "-dLastPage=1",
            "-dAutoRotatePages=/None",
        ] + bestPreviewQualityArguments() + [
            "-sDEVICE=pdfwrite",
            fileURL.path,
        ]

        let cArguments = arguments.map { strdup($0) }
        defer { cArguments.forEach { free($0) } }

        var argumentPointers = cArguments.map { UnsafeMutablePointer<CChar>($0) }
        let initResult = ghostscript.initWithArgs(ghostscriptInstance, Int32(arguments.count), &argumentPointers)

        guard initResult == 0 || initResult == -101 else {
            throw GhostscriptRenderingError.ghostscriptFailed(initResult)
        }

        return outputURL
    }

    private func bestPreviewQualityArguments() -> [String] {
        [
            "-dDownsampleColorImages=false",
            "-dDownsampleGrayImages=false",
            "-dDownsampleMonoImages=false",
            "-dAutoFilterColorImages=false",
            "-dAutoFilterGrayImages=false",
            "-dPassThroughJPEGImages=true",
            "-dPassThroughJPXImages=true",
            "-dEncodeColorImages=true",
            "-dEncodeGrayImages=true",
            "-dColorImageFilter=/FlateEncode",
            "-dGrayImageFilter=/FlateEncode",
        ]
    }

    private func parserExecutablePath() throws -> String {
        let resourceBundle = Bundle(for: GhostscriptResourceLocator.self)

        guard let parserURL = resourceBundle.url(forResource: "parser", withExtension: nil) else {
            throw GhostscriptRenderingError.missingBundledParser
        }

        return parserURL.path
    }

    private func normalizedFirstPageOutput(
        from outputURL: URL,
        fallbackFileURL: URL,
        sourceBoundingBox: EPSBoundingBox?
    ) throws -> NormalizedPDFOutput {
        let (document, page) = try loadFirstPage(from: outputURL)

        if let strategy = normalizationStrategy(
            for: page,
            sourceBoundingBox: sourceBoundingBox
        ) {
            let normalizedURL = try withExtendedLifetime(document) {
                try normalizedPreviewPDF(
                    from: outputURL,
                    page: page,
                    strategy: strategy
                )
            }
            return NormalizedPDFOutput(url: normalizedURL, contentSize: strategy.contentSize)
        }

        let contentSize = try pdfContentSize(
            for: outputURL,
            fallbackFileURL: fallbackFileURL,
            fallbackBoundingBox: sourceBoundingBox
        )
        return NormalizedPDFOutput(url: outputURL, contentSize: contentSize)
    }

    private func normalizationStrategy(
        for page: PDFPage,
        sourceBoundingBox: EPSBoundingBox?
    ) -> PDFNormalizationStrategy? {
        let (displayBox, pageRect) = preferredDisplayBox(for: page)
        let mediaBoxRect = normalizedRect(page.bounds(for: .mediaBox))

        if let sourceBoundingBox,
           pageRect.width > 0,
           pageRect.height > 0,
           rectsApproximatelyEqual(pageRect, sourceBoundingBox.rect) {
            return .pdfDisplayBox(displayBox: displayBox, rect: pageRect)
        }

        if let sourceBoundingBox,
           pageRect.width > 0,
           pageRect.height > 0 {
            return .epsBoundingBox(sourceBoundingBox)
        }

        if let sourceBoundingBox,
           mediaBoxRect.width > 0,
           mediaBoxRect.height > 0 {
            if rectsApproximatelyEqual(mediaBoxRect, sourceBoundingBox.rect) {
                return .pdfDisplayBox(displayBox: .mediaBox, rect: mediaBoxRect)
            }

            return .epsBoundingBox(sourceBoundingBox)
        }

        if pageRect.width > 0, pageRect.height > 0 {
            return .pdfDisplayBox(displayBox: displayBox, rect: pageRect)
        }

        return nil
    }

    private func pdfContentSize(
        for url: URL,
        fallbackFileURL: URL,
        fallbackBoundingBox: EPSBoundingBox?
    ) throws -> CGSize {
        if let document = PDFDocument(url: url),
           let page = document.page(at: 0) {
            let (_, pageRect) = preferredDisplayBox(for: page)
            let size = pageRect.size
            if size.width > 0, size.height > 0 {
                return size
            }
        }

        let boundingBox = try fallbackBoundingBox ?? EPSBoundingBoxParser.boundingBox(for: fallbackFileURL)
        if let boundingBox {
            return boundingBox.size
        }

        throw GhostscriptRenderingError.missingContentSize
    }

    private func preferredDisplayBox(for page: PDFPage) -> (PDFDisplayBox, CGRect) {
        let candidates: [(box: PDFDisplayBox, rect: CGRect)] = [
            (.cropBox, normalizedRect(page.bounds(for: .cropBox))),
            (.artBox, normalizedRect(page.bounds(for: .artBox))),
            (.trimBox, normalizedRect(page.bounds(for: .trimBox))),
            (.mediaBox, normalizedRect(page.bounds(for: .mediaBox))),
        ]

        for candidate in candidates where candidate.rect.width > 0 && candidate.rect.height > 0 {
            return candidate
        }

        return (.mediaBox, .zero)
    }

    private func normalizedPreviewPDF(
        from sourceURL: URL,
        page: PDFPage,
        strategy: PDFNormalizationStrategy
    ) throws -> URL {
        guard let pageRef = page.pageRef else {
            throw GhostscriptRenderingError.missingPageReference
        }

        let normalizedURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("normalized-preview")
            .appendingPathExtension("pdf")

        var mediaBox = CGRect(origin: .zero, size: strategy.contentSize)
        guard let context = CGContext(normalizedURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw GhostscriptRenderingError.failedToCreateNormalizedPDF
        }

        let pageInfo: [CFString: CGRect] = [
            kCGPDFContextMediaBox: mediaBox,
            kCGPDFContextCropBox: mediaBox,
        ]

        context.beginPDFPage(pageInfo as CFDictionary)
        context.saveGState()

        switch strategy {
        case let .pdfDisplayBox(displayBox, rect):
            let targetRect = CGRect(origin: .zero, size: rect.size)
            let transform = pageRef.getDrawingTransform(
                displayBox.cgPDFBox,
                rect: targetRect,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.concatenate(transform)
            context.drawPDFPage(pageRef)
        case let .epsBoundingBox(boundingBox):
            let targetRect = CGRect(origin: .zero, size: boundingBox.size)
            context.clip(to: targetRect)
            context.translateBy(x: -boundingBox.rect.origin.x, y: -boundingBox.rect.origin.y)
            context.drawPDFPage(pageRef)
        }

        context.restoreGState()
        context.endPDFPage()
        context.closePDF()

        return normalizedURL
    }

    private func normalizedRect(_ rect: CGRect) -> CGRect {
        rect.standardized
    }

    private func rectsApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        sizesApproximatelyEqual(lhs.size, rhs.size, tolerance: tolerance)
    }

    private func sizesApproximatelyEqual(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
    }

}

extension PDFDisplayBox {
    var cgPDFBox: CGPDFBox {
        switch self {
        case .mediaBox:
            return .mediaBox
        case .cropBox:
            return .cropBox
        case .bleedBox:
            return .bleedBox
        case .trimBox:
            return .trimBox
        case .artBox:
            return .artBox
        @unknown default:
            return .mediaBox
        }
    }
}
