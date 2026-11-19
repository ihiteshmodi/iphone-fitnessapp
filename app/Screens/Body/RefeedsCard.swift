import FitnessCore
import SwiftUI

/// While cutting: choose refeed days, see what a refeed is, mark the day. Hidden when not cutting.
struct RefeedsCard: View {
    let today: ISODate
    let maintenance: Double?

    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var weekdays: Set<Int> = []
    @State private var dates: [ISODate] = []
    @State private var cutStart: ISODate?
    @State private var isRefeedToday = false
    @State private var todayMark: RefeedMark?
    @State private var newDate = Date()

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        Group {
            if let cutStart {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Refeeds · cutting \(today.days(since: cutStart) / 7) weeks")
                    if isRefeedToday { todayCard }
                    Text("Refeed days").font(.system(size: 12)).foregroundColor(Theme.muted)
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            Button(Self.letters[day - 1]) { toggle(day) }
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 32, height: 32)
                                .foregroundColor(weekdays.contains(day) ? Theme.onGreen : Theme.muted)
                                .background(weekdays.contains(day) ? Theme.green : Theme.card2)
                                .clipShape(Circle())
                                .accessibilityLabel(PlanViewModel.weekdayNames[day - 1])
                                .accessibilityIdentifier("refeed-weekday-\(day)")
                        }
                    }
                    HStack {
                        DatePicker("Also on", selection: $newDate, in: Date()..., displayedComponents: .date).tint(Theme.green)
                        Button("Add") { run { try services.refeeds.addDate(BodyDates.day(from: newDate)) } }
                            .font(.system(size: 13, weight: .semibold))
                            .accessibilityIdentifier("refeed-add-date")
                    }
                    ForEach(dates.filter { $0 >= today }, id: \.self) { day in
                        HStack {
                            Text(Format.weekdayDate(day)).font(.system(size: 13)).foregroundColor(Theme.text)
                            Spacer()
                            Button("Remove") { run { try services.refeeds.removeDate(day) } }.font(.system(size: 12))
                        }
                    }
                    Text("Vault: a refeed is 1-2 days at maintenance, the extra calories mostly from carbs, protein and fat unchanged; the scale jump after it is water and glycogen. A diet break is 1-2 weeks at maintenance every 6-12 weeks of dieting.")
                        .font(.system(size: 11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                .card()
                .accessibilityIdentifier("refeeds-card")
            }
        }
        .task(id: session.revision) { load() }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today is a refeed day").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
            if let maintenance {
                Text("\(BodyNumbers.grouped(RefeedService.target(maintenance: maintenance))) kcal · extra mostly carbs, protein and fat unchanged")
                    .font(.system(size: 12)).foregroundColor(Theme.text)
            }
            HStack(spacing: 6) {
                ForEach(RefeedMark.allCases, id: \.self) { mark in
                    Button(mark.title) { run { try services.refeeds.mark(todayMark == mark ? nil : mark, on: today) } }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(todayMark == mark ? Theme.onGreen : Theme.green)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(todayMark == mark ? Theme.green : Theme.card2)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("refeed-mark-\(mark.rawValue)")
                }
            }
        }
        .padding(10)
        .background(Theme.green.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func toggle(_ day: Int) {
        var next = weekdays
        if next.contains(day) { next.remove(day) } else { next.insert(day) }
        run { try services.refeeds.setWeekdays(next) }
    }

    private func load() {
        cutStart = try? RefeedService.cutStart(on: today, db: services.db)
        weekdays = (try? services.refeeds.weekdays()) ?? []
        dates = (try? services.refeeds.dates()) ?? []
        isRefeedToday = (try? services.refeeds.isRefeedDay(today)) ?? false
        todayMark = try? services.refeeds.mark(on: today)
    }

    private func run(_ action: () throws -> Void) {
        try? action()
        session.didChange()
        load()
    }
}
