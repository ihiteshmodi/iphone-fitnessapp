import Foundation

/// Where UI tests find the seeded database. The simulator cannot read ~/Desktop (macOS privacy prompt hangs the
/// app), so `scripts/run-ui-tests.sh` copies output/fitness.seed.sqlite to /Users/Shared first.
enum UITestSeed {
    static let sharedPath = "/Users/Shared/fitness-ui-seed.sqlite"

    static var path: String {
        if FileManager.default.fileExists(atPath: sharedPath) { return sharedPath }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return repository.appendingPathComponent("output/fitness.seed.sqlite").path
    }

    static var launchArguments: [String] { ["-UITestImportPath", path] }
}
