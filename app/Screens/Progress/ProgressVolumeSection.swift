import FitnessCore
import SwiftUI

/// "Volume by muscle": muscle chips and one line per exercise for the selected muscle.
struct ProgressVolumeSection: View {
    @ObservedObject var model: ProgressViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Volume by muscle")
            if model.muscles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No sets logged yet").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                    Text("Log sets in the Workout tab and each muscle's volume (weight × reps) shows up here.")
                        .font(.system(size: 13)).foregroundColor(Theme.muted)
                }
                .card()
            } else {
                chips
                VStack(alignment: .leading, spacing: 8) {
                    BodyScrollableChart(points: model.volumePoints, columns: model.volumeColumns,
                                        seriesColors: model.seriesColors, minimumColumnWidth: 40)
                    legend
                }
                .card()
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.muscles, id: \.self) { muscle in
                    let selected = muscle == model.selectedMuscle
                    Button(muscle) { model.select(muscle: muscle) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? Theme.onGreen : Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.green : Theme.card2)
                        .overlay(Capsule().stroke(Theme.line))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("volume-chip-\(muscle)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.legend, id: \.name) { item in
                HStack(spacing: 6) {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(item.name).font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            }
        }
    }
}
