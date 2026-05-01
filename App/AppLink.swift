import Foundation

enum AppLink: String {
    case changelog = "https://flew.gg/eps-quick-look/changelog"
    case contact = "mailto:contact@flew.gg"
    case discord = "https://discord.gg/KUY56kppHn"
    case feedback = "https://github.com/flewgg/EPS-Quick-Look/issues/new"
    case privacy = "https://flew.gg/privacy"
    case releaseNotes = "https://flew.gg/eps-quick-look/releases"

    var url: URL {
        guard let url = URL(string: rawValue) else {
            preconditionFailure("Invalid app link URL: \(rawValue)")
        }
        return url
    }
}
