import os
import Quartz

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(subsystem: "gg.flew.eps", category: "Preview")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let renderedPreview: RenderedPDFPreview
        do {
            renderedPreview = try GhostscriptDocumentRenderer().renderPDFPreview(for: request.fileURL)
        } catch {
            // Quick Look reports a thrown error only as "Context size invalid in preview
            // generation", so say what actually went wrong where Console can show it.
            Self.logger.error("Preview failed: \(error.renderFailureSummary, privacy: .public)")
            throw error
        }

        return QLPreviewReply(
            dataOfContentType: .pdf,
            contentSize: renderedPreview.contentSize
        ) { _ in
            try Data(contentsOf: renderedPreview.url)
        }
    }
}
