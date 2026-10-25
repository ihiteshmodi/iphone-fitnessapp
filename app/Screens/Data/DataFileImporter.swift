import SwiftUI
import UniformTypeIdentifiers

/// File types the importer accepts. `.sqlite` files have no system type on every iOS version, so `.data` and `.item` are the safety net.
enum DataImportTypes {
    static var allowed: [UTType] {
        var types: [UTType] = [.data, .item]
        if let sqlite = UTType(filenameExtension: "sqlite") { types.append(sqlite) }
        return types
    }
}

private struct DataFileImporterModifier: ViewModifier {
    @EnvironmentObject private var session: AppSession
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    let onImported: () -> Void

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: DataImportTypes.allowed, allowsMultipleSelection: false) { result in
            switch result {
            case .failure(let error):
                errorMessage = MoreErrorText.message(for: error)
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try session.importDatabase(from: url)
                    onImported()
                } catch {
                    errorMessage = MoreErrorText.message(for: error)
                }
            }
        }
    }
}

extension View {
    /// Single-file picker that imports the chosen database through the session; failures go to `errorMessage`.
    func dataFileImporter(isPresented: Binding<Bool>, errorMessage: Binding<String?>, onImported: @escaping () -> Void = {}) -> some View {
        modifier(DataFileImporterModifier(isPresented: isPresented, errorMessage: errorMessage, onImported: onImported))
    }
}
