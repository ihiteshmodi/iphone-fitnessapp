import FitnessCore
import Foundation
import SwiftUI

/// Owns the open database and tells screens when data changed. Screens reload with `.task(id: session.revision)`.
@MainActor
final class AppSession: ObservableObject {
    enum Phase: Equatable {
        case loading
        case needsImport
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var revision = 0
    @Published private(set) var lastExport: ISODate?
    /// What the first screen shows when there is no database yet: any database file already in the app folder,
    /// the folder itself, and the names of the files in it, so a file copied in by hand is never invisible.
    @Published private(set) var foundDatabases: [URL] = []
    @Published private(set) var folderListing: [String] = []
    private(set) var folderPath = ""
    private(set) var services: Services?

    let clock: AppClock = SystemClock()
    private var fileService: DatabaseFileService?

    private static let lastExportKey = "lastExportDate"

    init() {
        lastExport = UserDefaults.standard.string(forKey: Self.lastExportKey).flatMap { ISODate($0) }
        do {
            let location = try AppDatabaseLocation.documents()
            folderPath = location.directory.path
            fileService = DatabaseFileService(location: location)
        } catch {
            phase = .failed("Cannot create the app data folder: \(error.localizedDescription)")
        }
    }

    func start() {
        guard let fileService, phase == .loading else { return }
        // Simulator tests pass a database path on the command line; ignored in normal use.
        if let path = UserDefaults.standard.string(forKey: "UITestImportPath") {
            try? fileService.importDatabase(from: URL(fileURLWithPath: path), clock: clock)
        }
        open()
    }

    /// Looks at the app folder again, for a file that was copied in while the app was open.
    func recheck() { open() }

    /// Refreshes the list of database files lying in the app folder (for restoring from More) without reopening anything.
    func refreshFoundDatabases() {
        guard let fileService else { return }
        foundDatabases = fileService.foundDatabases()
        folderListing = fileService.folderListing()
    }

    /// Call after any write so screens refresh.
    func didChange() { revision += 1 }

    func importDatabase(from url: URL) throws {
        guard let fileService else { throw ValidationError("The app data folder is not available") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // The old connection must be closed before the file is replaced.
        services = nil
        defer { open() }
        try fileService.importDatabase(from: url, clock: clock)
    }

    /// The seeded database shipped inside the app, so first launch works without any file picker.
    private static var bundledDatabaseURL: URL? { Bundle.main.url(forResource: "fitness", withExtension: "sqlite") }

    var hasBundledData: Bool { Self.bundledDatabaseURL != nil }

    func loadBundledData() throws {
        guard let url = Self.bundledDatabaseURL else { throw ValidationError("This app does not include any data") }
        try importDatabase(from: url)
    }

    /// Starts with an empty database; nothing is imported.
    func startEmpty() throws {
        guard let fileService else { throw ValidationError("The app data folder is not available") }
        services = nil
        defer { open() }
        try fileService.createEmptyDatabase()
    }

    /// Writes a dated copy into a temporary folder and returns it for the share sheet.
    func exportDatabase() throws -> URL {
        guard let fileService, let services else { throw ValidationError("There is no database to export") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try fileService.export(from: services.db, clock: clock, to: directory)
        let today = clock.today()
        lastExport = today
        UserDefaults.standard.set(today.string, forKey: Self.lastExportKey)
        return file
    }

    private func open() {
        guard let fileService else { return }
        do {
            if let db = try fileService.openLiveDatabase() {
                services = Services(db: db, clock: clock)
                phase = .ready
            } else {
                services = nil
                foundDatabases = fileService.foundDatabases()
                folderListing = fileService.folderListing()
                phase = .needsImport
            }
            revision += 1
        } catch {
            services = nil
            phase = .failed(error.localizedDescription)
        }
    }
}
