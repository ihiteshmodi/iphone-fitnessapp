import FitnessCore
import Foundation
import SwiftUI

/// What the Backup card says about the last export.
struct MoreBackupStatus: Equatable {
    let dateText: String?
    let agoText: String?
    let isStale: Bool

    static let staleAfterDays = 7

    static func make(lastExport: ISODate?, today: ISODate) -> MoreBackupStatus {
        guard let lastExport else { return MoreBackupStatus(dateText: nil, agoText: nil, isStale: true) }
        let days = max(today.days(since: lastExport), 0)
        let ago: String
        switch days {
        case 0: ago = "today"
        case 1: ago = "yesterday"
        default: ago = "\(days) days ago"
        }
        return MoreBackupStatus(dateText: Format.shortDate(lastExport), agoText: ago, isStale: days >= staleAfterDays)
    }
}

/// Loads and changes the settings shown on the More tab.
@MainActor
final class MoreViewModel: ObservableObject {
    static let multiplierStep = 0.05

    @Published private(set) var settings: AppSettings?
    @Published private(set) var exerciseCount = 0
    @Published private(set) var dayCount = 0
    @Published var errorMessage: String?

    private var link = MoreServiceLink()

    func bind(_ services: Services, notify: @escaping () -> Void) {
        link.bind(services, notify: notify)
        load()
    }

    func load() {
        guard let services = link.services else { return }
        do {
            settings = try services.settings.load()
            exerciseCount = try services.library.all().count
            dayCount = try services.workout.days().count
        } catch {
            errorMessage = MoreErrorText.message(for: error)
        }
    }

    var daysSummary: String { dayCount == 1 ? "1 day" : "\(dayCount) days" }
    var exercisesSummary: String { exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises" }

    var historyStart: Date {
        guard let settings else { return Date() }
        return Self.date(from: settings.historyStartDate)
    }

    func setDeloadEnabled(_ enabled: Bool) { change { try $0.setDeloadEnabled(enabled) } }
    func setIgnoreDeloadSessions(_ ignore: Bool) { change { try $0.setIgnoreDeloadSessions(ignore) } }
    func setDayLabelMode(_ mode: DayLabelMode) { change { try $0.setDayLabelMode(mode) } }

    func stepWeightMultiplier(by direction: Int) {
        guard let current = settings?.deload.weightMultiplier else { return }
        let next = Self.stepped(current, direction: direction)
        change { try $0.setDeloadWeightMultiplier(next) }
    }

    func stepRepsMultiplier(by direction: Int) {
        guard let current = settings?.deload.repsMultiplier else { return }
        let next = Self.stepped(current, direction: direction)
        change { try $0.setDeloadRepsMultiplier(next) }
    }

    func setHistoryStart(_ date: Date) {
        let text = ISODate(date: date).string
        change { try $0.setHistoryStartDate(text) }
    }

    func canDecrement(_ value: Double) -> Bool { value - Self.multiplierStep >= Self.multiplierStep - 0.0001 }

    private func change(_ work: (SettingsRepository) throws -> Void) {
        guard let services = link.services else { return }
        do {
            try work(services.settings)
            load()
            link.didChange()
        } catch {
            errorMessage = MoreErrorText.message(for: error)
            load()
        }
    }

    /// Rounded to hundredths so repeated steps never drift (0.75 + 0.05 stays 0.8).
    private static func stepped(_ value: Double, direction: Int) -> Double {
        max(((value + Double(direction) * multiplierStep) * 100).rounded() / 100, multiplierStep)
    }

    private static func date(from iso: ISODate) -> Date {
        let parts = iso.string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return Calendar.current.date(from: components) ?? Date()
    }
}
