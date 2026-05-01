import Foundation
import XCTest

final class TemporaryCleanupIntervalOptionTests: XCTestCase {
    func testDefaultOptionKeepsGeneratedFilesForThreeDays() {
        XCTAssertEqual(TemporaryCleanupIntervalOption.defaultOption, .threeDays)
    }

    func testTitlesMatchSettingsMenuLabels() {
        XCTAssertEqual(TemporaryCleanupIntervalOption.oneHour.title, "1 hour")
        XCTAssertEqual(TemporaryCleanupIntervalOption.twelveHours.title, "12 hours")
        XCTAssertEqual(TemporaryCleanupIntervalOption.oneDay.title, "1 day")
        XCTAssertEqual(TemporaryCleanupIntervalOption.threeDays.title, "3 days")
    }

    func testRetentionIntervalsUseExpectedDurations() {
        XCTAssertEqual(TemporaryCleanupIntervalOption.oneHour.retentionInterval, 60 * 60)
        XCTAssertEqual(TemporaryCleanupIntervalOption.twelveHours.retentionInterval, 12 * 60 * 60)
        XCTAssertEqual(TemporaryCleanupIntervalOption.oneDay.retentionInterval, 24 * 60 * 60)
        XCTAssertEqual(TemporaryCleanupIntervalOption.threeDays.retentionInterval, 3 * 24 * 60 * 60)
    }
}
