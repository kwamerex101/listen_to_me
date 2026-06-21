import XCTest
@testable import ListenToMe

final class UninstallerTests: XCTestCase {
    func test_appSupportURL_points_at_ListenToMe_support_dir() {
        XCTAssertEqual(Uninstaller.appSupportURL.lastPathComponent, "ListenToMe")
        XCTAssertTrue(Uninstaller.appSupportURL.path.contains("Application Support"))
    }

    func test_dailyNotesURL_points_at_documents_daily() {
        XCTAssertEqual(Uninstaller.dailyNotesURL.lastPathComponent, "daily")
        XCTAssertTrue(Uninstaller.dailyNotesURL.path.contains("Documents"))
    }

    func test_removalPlan_excludes_daily_notes_when_flag_false() {
        let plan = Uninstaller.removalPlan(includeDailyNotes: false)
        XCTAssertFalse(plan.contains(Uninstaller.dailyNotesURL))
    }

    func test_removalPlan_includes_daily_notes_only_when_present_and_opted_in() {
        // dailyNotes is included only if it exists on disk AND the flag is set.
        let plan = Uninstaller.removalPlan(includeDailyNotes: true)
        let exists = FileManager.default.fileExists(atPath: Uninstaller.dailyNotesURL.path)
        XCTAssertEqual(plan.contains(Uninstaller.dailyNotesURL), exists)
    }
}
