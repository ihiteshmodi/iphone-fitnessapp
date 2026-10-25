import FitnessCore
import SwiftUI

/// Exercise library (mockup 9): browse, create, edit and delete exercises.
struct LibraryView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @StateObject private var browser = LibraryBrowserModel()
    @State private var formTarget: LibraryFormTarget?

    var body: some View {
        VStack(spacing: 10) {
            LibrarySearchField(text: $browser.searchText)
                .padding(.horizontal, 16)
            LibraryMuscleChips(muscles: browser.muscles, selection: $browser.selectedMuscle)
                .padding(.horizontal, 16)
            List {
                Section {
                    ForEach(browser.results) { exercise in
                        Button { formTarget = .edit(exercise) } label: { row(exercise) }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.card)
                            .listRowSeparatorTint(Theme.line)
                            .accessibilityIdentifier("library-exercise-row")
                    }
                } footer: {
                    Text("Exercises with history cannot be deleted. Remove them from days instead. Names are unique ignoring case.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .padding(.top, 6)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if browser.results.isEmpty {
                    Text("No exercises match").font(.system(size: 14)).foregroundColor(Theme.muted)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("+ New") { formTarget = .create }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("library-new-button")
            }
        }
        .task(id: session.revision) { browser.bind(services) }
        .sheet(item: $formTarget) { target in
            LibraryExerciseFormView(mode: target.mode)
        }
        .errorAlert($browser.errorMessage)
    }

    private func row(_ exercise: Exercise) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.system(size: 15)).foregroundColor(Theme.text)
                Text(LibraryBrowserModel.libraryDetail(of: exercise)).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private enum LibraryFormTarget: Identifiable {
    case create
    case edit(Exercise)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let exercise): return "edit-\(exercise.id)"
        }
    }

    var mode: LibraryFormMode {
        switch self {
        case .create: return .create
        case .edit(let exercise): return .edit(exercise)
        }
    }
}
