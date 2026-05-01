import Foundation

extension Bundle {
    var appName: String {
        infoDictionary?["CFBundleDisplayName"] as? String
            ?? infoDictionary?["CFBundleName"] as? String
            ?? "Unknown"
    }

    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var versionWithBuild: String {
        "\(appVersion) (\(buildNumber))"
    }

    var copyright: String {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© \(Calendar.current.component(.year, from: Date())) flew. All rights reserved."
    }
}
