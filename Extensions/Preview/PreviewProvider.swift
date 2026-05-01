import Quartz

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let renderer = GhostscriptDocumentRenderer()
        let renderedPreview = try renderer.renderPDFPreview(for: request.fileURL)

        return QLPreviewReply(
            dataOfContentType: .pdf,
            contentSize: renderedPreview.contentSize
        ) { _ in
            try Data(contentsOf: renderedPreview.url)
        }
    }
}
