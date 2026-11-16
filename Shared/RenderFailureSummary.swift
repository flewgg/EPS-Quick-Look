import Foundation

extension Error {
    /// The error's domain and code, and those of the error under it, such as
    /// "NSCocoaErrorDomain 257 (NSPOSIXErrorDomain 1)". It names no files, so it
    /// can be logged publicly and pasted into a bug report.
    var renderFailureSummary: String {
        let error = self as NSError
        var summary = "\(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            summary += " (\(underlying.domain) \(underlying.code))"
        }
        return summary
    }
}
