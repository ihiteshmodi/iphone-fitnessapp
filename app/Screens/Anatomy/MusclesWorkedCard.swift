import FitnessCore
import SwiftUI

/// The small "Muscles worked" card: zooms on the primary muscles and lists them. Tapping Edit opens the editor.
struct MusclesWorkedCard: View {
    let muscles: ExerciseMuscles
    let onEdit: () -> Void

    private var frames: [MuscleFrame] { MuscleFigureCrop.frames(for: muscles.assignments) }

    private func names(_ parts: [MusclePart]) -> String { parts.map(\.displayName).joined(separator: ", ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Muscles worked")
                Spacer()
                Button(muscles.assignments.isEmpty ? "Choose muscles" : "Edit", action: onEdit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("muscles-edit-button")
            }

            if muscles.assignments.isEmpty {
                Text("No muscles yet. Tap Choose muscles to set them for this exercise.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(frames, id: \.view) { frame in
                            MuscleFigureView(view: frame.view, assignments: muscles.assignments, frame: frame.rect)
                                .frame(width: 92, height: 92)
                                .background(Color(hex: 0x101412))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: 6) {
                        if !muscles.primary.isEmpty {
                            legend("Primary", names(muscles.primary), color: Theme.green, bold: true)
                        }
                        if !muscles.secondary.isEmpty {
                            legend("Secondary", names(muscles.secondary), color: Theme.greenSoft, bold: false)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(muscles.isCustom ? "Customised" : "Automatic from the exercise name")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("muscles-card")
    }

    private func legend(_ title: String, _ text: String, color: Color, bold: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundColor(Theme.muted)
            Text(text)
                .font(.system(size: 12.5, weight: bold ? .bold : .regular))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
