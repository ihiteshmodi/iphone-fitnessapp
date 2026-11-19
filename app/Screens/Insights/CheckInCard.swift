import FitnessCore
import SwiftUI

/// The optional check-in for a day. Every question can be skipped; tapping a chosen answer again clears it.
struct CheckInCard: View {
    let date: ISODate
    let meals: [String]

    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var answers = CheckInDay(urine: nil, heavySweat: nil, walkedAfter: [])
    @State private var showingSigns = false
    @State private var weekSigns = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Check-in · optional")
                Spacer()
                Text("skip any").font(.system(size: 11)).foregroundColor(Theme.muted)
            }
            Text("Urine colour").font(.system(size: 12)).foregroundColor(Theme.muted)
            HStack(spacing: 6) {
                ForEach(UrineColour.allCases, id: \.self) { colour in
                    chip(colour.title, swatch: swatch(colour), on: answers.urine == colour, id: "urine-\(colour.rawValue)") {
                        save { try services.checkIn.setUrine(answers.urine == colour ? nil : colour, on: date) }
                    }
                }
            }
            if !meals.isEmpty {
                Text("Walked 10-15 min after").font(.system(size: 12)).foregroundColor(Theme.muted)
                HStack(spacing: 6) {
                    ForEach(meals, id: \.self) { meal in
                        let walked = answers.walkedAfter.contains(meal)
                        chip(walked ? "\(meal) ✓" : meal, on: walked, id: "walk-\(meal)") {
                            save { try services.checkIn.setWalked(!walked, after: meal, on: date) }
                        }
                    }
                }
            }
            Text("Sweated heavily today?").font(.system(size: 12)).foregroundColor(Theme.muted)
            HStack(spacing: 6) {
                chip("Yes", on: answers.heavySweat == true, id: "sweat-yes") { save { try services.checkIn.setHeavySweat(answers.heavySweat == true ? nil : true, on: date) } }
                chip("No", on: answers.heavySweat == false, id: "sweat-no") { save { try services.checkIn.setHeavySweat(answers.heavySweat == false ? nil : false, on: date) } }
            }
            if answers.heavySweat == true {
                Text("Vault: heavy or long sweating needs about 300-700 mg sodium per hour (at least ~500 mg/h when heavy); a normal 45-60 min lift needs only water and electrolytes.")
                    .font(.system(size: 12)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                NavigationLink("Plan a sweaty activity") { SweatyActivityView() }
                    .font(.system(size: 12, weight: .semibold))
            }
            Button("This week's recovery signs (\(weekSigns))") { showingSigns = true }
                .font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("recovery-signs-button")
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check-in-card")
        .task(id: "\(date.string)-\(session.revision)") { load() }
        .sheet(isPresented: $showingSigns) { RecoverySignsSheet(date: date) { load() } }
    }

    private func load() {
        answers = (try? services.checkIn.day(date)) ?? answers
        weekSigns = (try? services.checkIn.signs(weekOf: date).count) ?? 0
    }

    private func save(_ action: () throws -> Void) {
        try? action()
        load()
        session.didChange()
    }

    private func swatch(_ colour: UrineColour) -> Color {
        switch colour {
        case .clear: return Color(hex: 0xF4F6EC)
        case .pale: return Color(hex: 0xF1E58A)
        case .dark: return Color(hex: 0xC9962B)
        }
    }

    private func chip(_ title: String, swatch: Color? = nil, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let swatch { RoundedRectangle(cornerRadius: 3).fill(swatch).frame(width: 12, height: 12) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(on ? Theme.onGreen : Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Theme.green : Theme.card2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("checkin-\(id)")
    }
}

/// Once a week: tick any sign noticed. Only 3 or more for two weeks in a row is flagged.
struct RecoverySignsSheet: View {
    let date: ISODate
    let onSaved: () -> Void
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var signs: Set<RecoverySign> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RecoverySign.allCases, id: \.self) { sign in
                        Toggle(sign.title, isOn: Binding(get: { signs.contains(sign) }, set: { if $0 { signs.insert(sign) } else { signs.remove(sign) } }))
                            .tint(Theme.green)
                    }
                } footer: {
                    Text("Week of \(Format.shortDate(CheckInService.monday(of: date))). One sign means little; 3 or more two weeks running is a pattern.")
                }
            }
            .navigationTitle("Recovery signs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? services.checkIn.setSigns(signs, weekOf: date)
                        session.didChange()
                        onSaved()
                        dismiss()
                    }
                }
            }
            .onAppear { signs = (try? services.checkIn.signs(weekOf: date)) ?? [] }
        }
    }
}

/// For a hike or any long sweaty activity: what to put in the water you carry.
struct SweatyActivityView: View {
    @State private var hours = "3"
    @State private var litres = "2"
    @State private var sweat = SweatyActivity.Sweat.heavy

    private var plan: SweatyActivity.Plan? {
        guard let h = Format.decimal(hours), let l = Format.decimal(litres) else { return nil }
        return try? SweatyActivity.plan(hours: h, sweat: sweat, bottleLitres: l)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your daily workout mix stays as it is. This is for long, sweaty activities only.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
                HStack(spacing: 10) {
                    BodyField(label: "Duration", text: $hours, unit: "h", identifier: "sweat-hours")
                    BodyField(label: "Carrying", text: $litres, unit: "L", identifier: "sweat-litres")
                }
                Picker("Sweat", selection: $sweat) {
                    Text("Light sweat").tag(SweatyActivity.Sweat.light)
                    Text("Heavy sweat").tag(SweatyActivity.Sweat.heavy)
                }
                .pickerStyle(.segmented)
                if let plan {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Put in your \(litres) L")
                        line("Himalayan salt", range(plan.saltGrams, "g"), "\(range(plan.sodiumMg, "mg", decimals: 0)) sodium")
                        line("Potassium chloride", range(plan.potassiumChlorideGrams, "g"), "\(range(plan.potassiumMg, "mg", decimals: 0)) potassium")
                        line("Sip", "\(range(plan.sipMl, "mL", decimals: 0))", "every 15-20 min")
                    }
                    .card(highlighted: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("sweat-plan")
                }
                Text("Vault: 300-700 mg sodium per hour (at least ~500 mg/h when sweating heavily), 80-150 mg potassium per 500-750 mL in long or hot sessions, 180-360 mL every 15-20 min. Salt is about 38% sodium and potassium chloride 52% potassium (chemistry).")
                    .font(.system(size: 11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Sweaty activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func range(_ r: ClosedRange<Double>, _ unit: String, decimals: Int = 1) -> String {
        let a = Format.number(r.lowerBound, maxDecimals: decimals), b = Format.number(r.upperBound, maxDecimals: decimals)
        return a == b ? "\(a) \(unit)" : "\(a)-\(b) \(unit)"
    }

    private func line(_ name: String, _ value: String, _ note: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14)).foregroundColor(Theme.text)
                Text(note).font(.system(size: 11)).foregroundColor(Theme.muted)
            }
            Spacer()
            Text(value).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
        }
    }
}
