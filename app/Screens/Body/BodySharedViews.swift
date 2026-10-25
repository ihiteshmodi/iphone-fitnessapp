import FitnessCore
import SwiftUI

// Small building blocks shared by the Body and Progress screens.

/// Small caption above a big screen title, as in the mockups.
struct BodyHeader: View {
    let caption: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(.system(size: 12)).foregroundColor(Theme.muted)
            Text(title).font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Conversions between the app's calendar days and the system date picker.
enum BodyDates {
    static func date(from day: ISODate) -> Date {
        let parts = day.string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        // Noon keeps the picked day stable across time zones.
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }

    static func day(from date: Date) -> ISODate { ISODate(date: date) }
}

/// Ghost button in red, for removing things.
struct BodyDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Theme.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.card2)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A labelled text field on a card-coloured background.
struct BodyField: View {
    let label: String
    @Binding var text: String
    var unit: String? = nil
    var identifier: String
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            HStack {
                TextField("", text: $text)
                    .keyboardType(keyboard)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .accessibilityIdentifier(identifier)
                if let unit {
                    Text(unit).font(.system(size: 14)).foregroundColor(Theme.muted)
                }
            }
            .padding(12)
            .background(Theme.card2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// "18 Oct ... 14.00 in ✎" row that opens an edit sheet when tapped.
struct BodyHistoryRow: View {
    let date: String
    let value: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(date).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Text(value).font(.system(size: 14)).foregroundColor(Theme.text)
                Text("✎").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.green)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// One number (and optionally a date) with Save and an optional Delete: weigh-ins, readings and targets.
struct BodyValueEntrySheet: View {
    let title: String
    let fieldLabel: String
    let unit: String
    var initialText = ""
    /// Nil hides the date picker; the sheet then reports today's date to `onSave`.
    var initialDate: ISODate?
    let today: ISODate
    var deleteTitle: String?
    var onDelete: (() throws -> Void)?
    let onSave: (Double, ISODate) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var prepared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BodyField(label: fieldLabel, text: $text, unit: unit, identifier: "value-field")
                    if initialDate != nil {
                        HStack {
                            SectionLabel("Date")
                            Spacer()
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .accessibilityIdentifier("date-picker")
                        }
                    }
                    if let deleteTitle, onDelete != nil {
                        Button(deleteTitle) { confirmingDelete = true }
                            .buttonStyle(BodyDestructiveButtonStyle())
                            .accessibilityIdentifier("sheet-delete-button")
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).accessibilityIdentifier("sheet-save-button")
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
                Button("Keep", role: .cancel) {}
            }
            .errorAlert($errorMessage)
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            text = initialText
            date = BodyDates.date(from: initialDate ?? today)
        }
    }

    private func save() {
        guard let value = Format.decimal(text) else {
            errorMessage = "Enter \(fieldLabel.lowercased()) as a number"
            return
        }
        do {
            try onSave(value, initialDate == nil ? today : BodyDates.day(from: date))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try onDelete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Line chart that scrolls sideways once there are more points than fit, starting at the newest.
struct BodyScrollableChart: View {
    let points: [ChartPoint]
    /// Number of distinct x positions (dates) in `points`.
    let columns: Int
    var targetLine: Double?
    var seriesColors: [String: Color] = [:]
    var height: CGFloat = 150
    /// 0 keeps the chart at the card width.
    var minimumColumnWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    TrendChart(points: points, targetLine: targetLine, height: height, seriesColors: seriesColors)
                        .frame(width: max(proxy.size.width, CGFloat(columns) * minimumColumnWidth))
                        .id("chart")
                }
                .onAppear { scroller.scrollTo("chart", anchor: .trailing) }
            }
        }
        .frame(height: height)
    }
}
