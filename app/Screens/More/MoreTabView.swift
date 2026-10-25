import FitnessCore
import SwiftUI

struct MoreTabView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = MoreViewModel()

    @State private var shareItem: MoreShareItem?
    @State private var isImporterPresented = false
    @State private var importedNotice = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    backupCard
                    deloadCard
                    historyCard
                    planCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("More")
        }
        .task(id: session.revision) {
            model.bind(services) { session.didChange() }
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .dataFileImporter(isPresented: $isImporterPresented, errorMessage: $errorMessage) { importedNotice = true }
        .errorAlert($errorMessage)
        .errorAlert($model.errorMessage)
        .alert("Database imported", isPresented: $importedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data was replaced. A safety copy of the previous database was kept.")
        }
    }

    // MARK: Backup

    private var backupCard: some View {
        let status = MoreBackupStatus.make(lastExport: session.lastExport, today: session.clock.today())
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Backup")
            backupSummary(status)
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
                .accessibilityIdentifier("last-export-text")
            Button("Export database (.sqlite)", action: export)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("export-database-button")
            Button("Import database") { isImporterPresented = true }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .accessibilityIdentifier("import-database-more-button")
            Text("Export, then save to Google Drive from the share sheet. Weekly.")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
        }
        .card()
    }

    private func backupSummary(_ status: MoreBackupStatus) -> Text {
        guard let dateText = status.dateText, let agoText = status.agoText else {
            return Text("Never exported").foregroundColor(Theme.amber)
        }
        let ago = Text(agoText).foregroundColor(status.isStale ? Theme.amber : Theme.muted)
        return Text("Last export ") + Text(dateText).bold() + Text(" · ") + ago
    }

    private func export() {
        do {
            shareItem = MoreShareItem(url: try session.exportDatabase())
        } catch {
            errorMessage = MoreErrorText.message(for: error)
        }
    }

    // MARK: Deload

    private var deloadCard: some View {
        let deload = model.settings?.deload
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Deload week")
            MoreRow(title: "Deload on", subtitle: "Only changes workout targets") {
                Toggle("Deload on", isOn: Binding(get: { deload?.enabled ?? false }, set: { model.setDeloadEnabled($0) }))
                    .labelsHidden()
                    .tint(Theme.green)
                    .accessibilityIdentifier("deload-toggle")
            }
            .padding(.top, 4)
            divider
            MoreRow(title: "Weight multiplier") {
                multiplierStepper(title: "Weight multiplier", value: deload?.weightMultiplier ?? 1, step: model.stepWeightMultiplier)
            }
            divider
            MoreRow(title: "Min reps multiplier") {
                multiplierStepper(title: "Min reps multiplier", value: deload?.repsMultiplier ?? 0.75, step: model.stepRepsMultiplier)
            }
            divider
            MoreRow(title: "Ignore deload sessions",
                    subtitle: "On: sets logged in deload week don't change working weights, trends, last session or volume. Off: they count like any other set.") {
                Toggle("Ignore deload sessions", isOn: Binding(get: { model.settings?.ignoreDeloadSessions ?? true },
                                                               set: { model.setIgnoreDeloadSessions($0) }))
                    .labelsHidden()
                    .tint(Theme.green)
                    .accessibilityIdentifier("ignore-deload-toggle")
            }
        }
        .card()
    }

    private func multiplierStepper(title: String, value: Double, step: @escaping (Int) -> Void) -> some View {
        MoreStepperControl(title: title, value: Format.fixed(value), canDecrement: model.canDecrement(value),
                           onDecrement: { step(-1) }, onIncrement: { step(1) })
    }

    // MARK: Progress history

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Progress history")
            MoreRow(title: "Count history from", subtitle: "Applies to everything: working weights, recommendations, trends and charts") {
                DatePicker("Count history from", selection: Binding(get: { model.historyStart }, set: { model.setHistoryStart($0) }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.green)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("history-start-row")
        }
        .card()
    }

    // MARK: Plan

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Plan")
            NavigationLink {
                EditPlanView()
            } label: {
                MoreRow(title: "Edit plan") { chevronValue(model.daysSummary) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("edit-plan-row")
            divider
            MoreRow(title: "Name days by") {
                Picker("Name days by", selection: Binding(get: { model.settings?.dayLabelMode ?? .number }, set: { model.setDayLabelMode($0) })) {
                    Text("Numbers").tag(DayLabelMode.number)
                    Text("Weekdays").tag(DayLabelMode.weekday)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityIdentifier("day-label-mode-picker")
            }
            divider
            NavigationLink {
                LibraryView()
            } label: {
                MoreRow(title: "Exercise library") { chevronValue(model.exercisesSummary) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-row")
        }
        .card()
    }

    private func chevronValue(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 14)).foregroundColor(Theme.muted)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
        }
    }

    private var divider: some View { Divider().overlay(Theme.line) }
}

private struct MoreShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
