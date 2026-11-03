import CoreGraphics
import ImageIO
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

private enum ThumbnailGenerationError: LocalizedError, CustomNSError {
    case missingPageReference
    case missingBitmapContext
    case missingImage
    case missingDestination
    case failedToWritePNG

    static var errorDomain: String {
        "EPSQuickLook.Thumbnail"
    }

    var errorCode: Int {
        switch self {
        case .missingPageReference:
            return 5
        case .missingBitmapContext:
            return 6
        case .missingImage:
            return 7
        case .missingDestination:
            return 8
        case .failedToWritePNG:
            return 9
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingPageReference:
            return "The rendered PDF page could not be rasterized."
        case .missingBitmapContext:
            return "The thumbnail bitmap context could not be created."
        case .missingImage:
            return "The thumbnail image could not be created."
        case .missingDestination:
            return "The thumbnail PNG destination could not be created."
        case .failedToWritePNG:
            return "The thumbnail PNG could not be written."
        }
    }
}

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let renderer = GhostscriptDocumentRenderer()
            let renderedPage = try renderer.renderFirstPage(for: request.fileURL)
            let replySize = normalizedReplySize(request.maximumSize, contentSize: renderedPage.pageRect.size)

            let imageURL = try rasterizedThumbnailImageURL(
                for: renderedPage,
                canvasSize: replySize,
                scale: max(request.scale, 1)
            )
            let reply = QLThumbnailReply(imageFileURL: imageURL)

            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    private func normalizedReplySize(_ requestedSize: CGSize, contentSize: CGSize) -> CGSize {
        guard requestedSize.width > 0, requestedSize.height > 0 else {
            return contentSize
        }

        let scale = min(requestedSize.width / contentSize.width, requestedSize.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    private func rasterizedThumbnailImageURL(
        for renderedPage: RenderedPDFPage,
        canvasSize: CGSize,
        scale: CGFloat
    ) throws -> URL {
        guard let pageRef = renderedPage.page.pageRef else {
            throw ThumbnailGenerationError.missingPageReference
        }

        let pixelWidth = max(Int(ceil(canvasSize.width * scale)), 1)
        let pixelHeight = max(Int(ceil(canvasSize.height * scale)), 1)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ThumbnailGenerationError.missingBitmapContext
        }

        let targetRect = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        let pageRect = renderedPage.pageRect

        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(targetRect)
        context.saveGState()
        context.scaleBy(x: targetRect.width / pageRect.width, y: targetRect.height / pageRect.height)
        context.translateBy(x: -pageRect.minX, y: -pageRect.minY)
        context.drawPDFPage(pageRef)
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw ThumbnailGenerationError.missingImage
        }

        let temporaryDirectory = try PreviewTemporaryStorage.makeManagedTemporaryDirectory(prefix: "Thumbnail")
        let imageURL = temporaryDirectory.appendingPathComponent("thumbnail").appendingPathExtension("png")

        guard let destination = CGImageDestinationCreateWithURL(
            imageURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ThumbnailGenerationError.missingDestination
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailGenerationError.failedToWritePNG
        }

        return imageURL
    }
}
