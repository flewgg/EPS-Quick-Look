import SwiftUI

struct AcknowledgementsWindowView: View {
    private let acknowledgmentsText = AcknowledgmentsDocument.load()

    var body: some View {
        ScrollView {
            Text(verbatim: acknowledgmentsText)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
    }
}

private enum AcknowledgmentsDocument {
    static func load() -> String {
        guard let url = Bundle.main.url(forResource: "Acknowledgments", withExtension: "txt") else {
            return """
            Acknowledgments are unavailable because Acknowledgments.txt could not be loaded from the app bundle.
            """
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return """
            Acknowledgments are unavailable because Acknowledgments.txt could not be read.

            \(error.localizedDescription)
            """
        }
    }
}
