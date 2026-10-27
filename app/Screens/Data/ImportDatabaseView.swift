import SwiftUI

/// First launch: the app has no database yet. Ways in, none of which can leave the app stuck: use a database file already
/// in the app folder, load the data shipped inside the app, pick a file, or start empty. The folder the app looks in,
/// and the files it sees there, are shown so a file copied in by hand can be checked.
struct ImportDatabaseView: View {
    @EnvironmentObject private var session: AppSession
    @State private var isPickerPresented = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 24)
                ZStack {
                    Circle().fill(Theme.green.opacity(0.15)).frame(width: 96, height: 96)
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(Theme.green)
                }
                Text("Set up your data")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("Everything stays on this phone and works offline.")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 16)

                if !session.foundDatabases.isEmpty { foundFiles }

                if session.hasBundledData {
                    Button("Load my data") { run { try session.loadBundledData() } }
                        .buttonStyle(PrimaryButtonStyle(ghost: !session.foundDatabases.isEmpty))
                        .accessibilityIdentifier("load-bundled-data-button")
                    Text("Your workout plan and full history, included in this app.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                }

                Button("Import a database file") { isPickerPresented = true }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .accessibilityIdentifier("import-database-button")
                Button("Start empty") { run { try session.startEmpty() } }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .accessibilityIdentifier("start-empty-button")

                whatTheAppSees

                Text("If the file picker will not let you select a file inside LiveContainer, hold this app, open Settings and turn on Fix File Picker.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .dataFileImporter(isPresented: $isPickerPresented, errorMessage: $errorMessage)
        .errorAlert($errorMessage)
    }

    /// Database files already in the app folder, usable with one tap and no picker.
    private var foundFiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Found in the app folder")
            ForEach(session.foundDatabases, id: \.self) { url in
                Button("Use \(url.lastPathComponent)") { run { try session.importDatabase(from: url) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("use-found-\(url.lastPathComponent)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var whatTheAppSees: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("What the app sees")
            Text("It looks for fitness.sqlite in:")
                .font(.system(size: 12)).foregroundColor(Theme.muted)
            Text(session.folderPath)
                .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.text)
                .textSelection(.enabled)
            Text(session.folderListing.isEmpty ? "No files there yet." : "Files there: \(session.folderListing.joined(separator: ", "))")
                .font(.system(size: 12)).foregroundColor(Theme.muted)
                .accessibilityIdentifier("folder-listing")
            Button("Check again") { session.recheck() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.green)
                .padding(.top, 2)
                .accessibilityIdentifier("check-again-button")
        }
        .card()
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = MoreErrorText.message(for: error) }
    }
}
