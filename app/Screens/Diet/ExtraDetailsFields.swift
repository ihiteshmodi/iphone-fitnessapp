import FitnessCore
import SwiftUI

/// A starting guess from the clock, so most extras need no tap; it can always be changed or cleared.
enum ExtraTimeGuess {
    static func now(_ date: Date = Date(), calendar: Calendar = .current) -> ExtraTime {
        switch calendar.component(.hour, from: date) {
        case ..<11: return .morning
        case ..<16: return .noon
        case ..<20: return .evening
        default: return .night
        }
    }
}

/// When an extra was eaten (tap again to clear) and a note.
struct ExtraDetailsFields: View {
    @Binding var time: ExtraTime?
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("When")
            HStack(spacing: 6) {
                ForEach(ExtraTime.allCases, id: \.self) { option in
                    Button(option.title) { time = time == option ? nil : option }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(time == option ? Theme.onGreen : Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(time == option ? Theme.green : Theme.card2)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("extra-time-\(option.rawValue)")
                }
            }
            TextField("Note (optional)", text: $note)
                .foregroundColor(Theme.text)
                .padding(12)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("extra-note-field")
        }
    }
}
