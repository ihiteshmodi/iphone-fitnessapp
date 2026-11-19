import FitnessCore
import SwiftUI

enum InsightTab: String, CaseIterable {
    case today = "Today", trends = "Trends", setup = "Setup", labs = "Labs", archived = "Archived"
}

@MainActor
final class RoomForImprovementModel: ObservableObject {
    @Published private(set) var todayItems: [Insight] = []
    @Published private(set) var setupItems: [Insight] = []
    @Published private(set) var trends: [TrendRow] = []
    @Published private(set) var archived: [ArchivedRule] = []
    @Published var trendDays = 30
    @Published var errorMessage: String?

    private let services: Services
    init(services: Services) { self.services = services }

    private var rooms: InsightService { services.insights }
    var today: ISODate { services.clock.today() }

    func load() {
        do {
            todayItems = try rooms.today(on: today)
            setupItems = try rooms.setup(on: today)
            trends = try rooms.trends(endingOn: today.adding(days: -1), days: trendDays)
            archived = try rooms.archived()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismiss(_ item: Insight) { perform { try self.rooms.dismiss(item) } }
    func accept(_ item: Insight) { perform { try self.rooms.accept(item) } }
    func notApplicable(_ item: Insight) { perform { try self.rooms.markNotApplicable(item.ruleID, title: item.title) } }
    func restore(_ rule: ArchivedRule) { perform { try self.rooms.restore(rule.ruleID) } }
    func run(_ action: InsightAction) {
        switch action {
        case .turnOnDeload: perform { try self.services.settings.setDeloadEnabled(true) }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// What could be better: today's items, how often each rule fired, one-time fixes to the plan, and what was put away.
struct RoomForImprovementView: View {
    @StateObject private var model: RoomForImprovementModel
    @State private var tab = InsightTab.today

    init(services: Services) { _model = StateObject(wrappedValue: RoomForImprovementModel(services: services)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Section", selection: $tab) {
                    ForEach(InsightTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insight-tabs")
                switch tab {
                case .today: items(model.todayItems, empty: "Nothing to fix from today or yesterday.")
                case .setup: items(model.setupItems, empty: "Your plan passes every check.")
                case .trends: trendsSection
                case .labs: note("Bloodwork-based items arrive with Blood Labs.")
                case .archived: archivedSection
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Room for improvement")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
        .errorAlert($model.errorMessage)
    }

    @ViewBuilder
    private func items(_ list: [Insight], empty: String) -> some View {
        if list.isEmpty { note(empty) }
        ForEach(list) { item in card(item) }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundColor(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func card(_ item: Insight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Pill(text: item.severity.title, tone: item.severity == .fix ? .red : (item.severity == .improve ? .amber : .grey))
                Text(item.title).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                if let day = item.day { Text(Format.shortDate(day)).font(.system(size: 11)).foregroundColor(Theme.muted) }
            }
            Text(item.detail).font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            Text(item.why).font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if item.action == .turnOnDeload {
                    Button("Turn on deload") { model.run(.turnOnDeload) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("turn-on-deload")
                }
                if item.kind == .today {
                    Button("Dismiss") { model.dismiss(item) }.accessibilityIdentifier("dismiss-\(item.id)")
                } else {
                    Button("Accept") { model.accept(item) }.accessibilityIdentifier("accept-\(item.id)")
                }
                Button("Doesn't apply to me") { model.notApplicable(item) }.accessibilityIdentifier("not-applicable-\(item.id)")
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .font(.system(size: 12))
        }
        .card()
        .accessibilityIdentifier("insight-\(item.id)")
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Days", selection: Binding(get: { model.trendDays }, set: { model.trendDays = $0; model.load() })) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)
            ForEach(model.trends) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        Text("\(row.firedCount) of \(row.daysWithData) days").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(row.firedCount > 0 ? Theme.amber : Theme.green)
                    }
                    TrendStrip(marks: row.marks)
                }
                .card()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("trend-\(row.ruleID)")
            }
            Text("Red = the rule fired, green = fine, grey = not enough data that day (unknown nutrients, nothing logged, a break).")
                .font(.system(size: 11)).foregroundColor(Theme.muted)
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if model.archived.isEmpty { note("Nothing put away.") }
        ForEach(model.archived) { rule in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    Text(rule.status == .accepted ? "Accepted · still tracked in Trends" : "Doesn't apply to me · not checked")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                    if let note = rule.note { Text(note).font(.system(size: 12)).italic().foregroundColor(Theme.muted) }
                }
                Spacer()
                Button("Restore") { model.restore(rule) }.font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("restore-\(rule.ruleID)")
            }
            .card()
        }
    }
}

/// One small square per day, oldest first.
struct TrendStrip: View {
    let marks: [TrendMark]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = marks.count > 40 ? 1 : 2
            let width = max((proxy.size.width - gap * CGFloat(max(marks.count - 1, 0))) / CGFloat(max(marks.count, 1)), 1)
            HStack(spacing: gap) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    RoundedRectangle(cornerRadius: 2).fill(color(mark)).frame(width: width, height: 12)
                }
            }
        }
        .frame(height: 12)
    }

    private func color(_ mark: TrendMark) -> Color {
        switch mark {
        case .fired: return Theme.red
        case .ok: return Theme.green.opacity(0.55)
        case .noData: return Theme.card2
        }
    }
}

/// The entry point on Today: how many things are waiting.
struct RoomForImprovementLink: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var count = 0

    var body: some View {
        NavigationLink { RoomForImprovementView(services: services) } label: {
            HStack {
                Text("Room for improvement").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                if count > 0 { Pill(text: "\(count)", tone: .amber) }
                Image(systemName: "chevron.right").foregroundColor(Theme.muted)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room-for-improvement-link")
        .task(id: session.revision) { count = (try? services.insights.badgeCount(on: services.clock.today())) ?? 0 }
    }
}
