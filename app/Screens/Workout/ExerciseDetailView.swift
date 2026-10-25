import FitnessCore
import SwiftUI

/// Exercise screen. Section order is fixed: everything needed to train comes first, logging is last.
struct ExerciseDetailView: View {
    @EnvironmentObject private var services: Services
    let exerciseId: Int
    let dayId: Int

    var body: some View {
        ExerciseDetailContent(services: services, exerciseId: exerciseId, dayId: dayId)
    }
}

private struct ExerciseDetailContent: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var vm: ExerciseDetailViewModel
    @State private var showingAddSet = false
    @State private var showingHowToEditor = false
    @State private var showingMuscleEditor = false

    init(services: Services, exerciseId: Int, dayId: Int) {
        _vm = StateObject(wrappedValue: ExerciseDetailViewModel(services: services, exerciseId: exerciseId, dayId: dayId))
    }

    var body: some View {
        ScrollView {
            if vm.detail != nil {
                VStack(spacing: 12) {
                    header
                    doToday
                    progress
                    howTo
                    musclesWorked
                    logSets
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { vm.load() }
        .sheet(isPresented: $showingAddSet) {
            DetailAddSetSheet(vm: vm, onSaved: { session.didChange() })
        }
        .sheet(isPresented: $showingHowToEditor) {
            DetailHowToEditor(vm: vm, onSaved: { session.didChange() })
        }
        .sheet(isPresented: $showingMuscleEditor) {
            if let muscles = vm.muscles {
                MuscleEditorSheet(
                    exerciseName: vm.name,
                    muscles: muscles,
                    onSave: { assignments in if vm.saveMuscles(assignments) { session.didChange() } },
                    onReset: { if vm.resetMuscles() { session.didChange() } })
            }
        }
        // The sheets show their own errors; two alerts bound to one message would fight.
        .errorAlert(showingAddSet || showingHowToEditor || showingMuscleEditor ? .constant(nil) : $vm.errorMessage)
    }

    // MARK: 1. Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.caption).font(.system(size: 13)).foregroundColor(Theme.muted)
                Text(vm.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            DetailTrendPill(badge: vm.trendBadge)
                .padding(.top, 4)
        }
    }

    // MARK: 2. Do today (weight, aim, warm-ups)

    private var doToday: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                SectionLabel("Do today")
                Spacer()
                if let aim = vm.aimSummary {
                    Pill(text: aim.pill, tone: vm.aimTone).accessibilityIdentifier("aim-pill")
                }
            }
            if let weight = vm.workingWeightText {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(weight).font(.system(size: 44, weight: .bold)).foregroundColor(Theme.text)
                            Text("kg").font(.system(size: 18)).foregroundColor(Theme.muted)
                        }
                        if let hint = vm.aimSummary?.hint {
                            Text(hint).font(.system(size: 13)).foregroundColor(Theme.green).accessibilityIdentifier("aim-hint")
                        }
                    }
                    Spacer()
                    if !vm.warmups.isEmpty {
                        VStack(alignment: .trailing, spacing: 3) {
                            SectionLabel("Warm-ups")
                            ForEach(vm.warmups) { warmup in
                                HStack(spacing: 6) {
                                    Text(warmup.percent).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.muted)
                                    Text(warmup.kg).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("No history yet").font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                Text("Log a first set to get a working weight.").font(.system(size: 13)).foregroundColor(Theme.muted)
            }
        }
        .card(padding: 16)
    }

    // MARK: 3. Best set per session

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Best set per session")
                Spacer()
                Text("kg above · reps below").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.green)
            }
            if vm.sessionPoints.isEmpty {
                Text("Your sessions will be charted here.").font(.system(size: 13)).foregroundColor(Theme.muted)
                    .padding(.vertical, 12)
            } else {
                SessionLineChart(points: vm.sessionPoints, height: 160)
            }
            Text(vm.trendText).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .card()
    }

    // MARK: 4. How to

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("How to")
                Spacer()
                Button("Edit") { showingHowToEditor = true }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("edit-howto-button")
            }
            if vm.instructions.isEmpty {
                Text("No instructions yet. Tap Edit to add some.")
                    .font(.system(size: 14)).foregroundColor(Theme.muted)
            } else {
                Text(vm.instructions)
                    .font(.system(size: 14)).foregroundColor(Theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("howto-text")
            }
        }
        .card()
    }

    // MARK: 5. Muscles worked

    private var musclesWorked: some View {
        Group {
            if let muscles = vm.muscles {
                MusclesWorkedCard(muscles: muscles, onEdit: { showingMuscleEditor = true })
            }
        }
    }

    // MARK: 6. Log sets (always last)

    private var logSets: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Log sets · today")
                Spacer()
                Text(vm.todayCountText).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.green)
            }
            ForEach(Array(vm.todaySets.enumerated()), id: \.element.id) { index, set in
                todayRow(number: index + 1, set: set)
            }
            ForEach(vm.emptySlotNumbers, id: \.self) { number in
                emptyRow(number: number)
            }
            Button { showingAddSet = true } label: { Text("+ Add set") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
                .accessibilityIdentifier("add-set-button")
        }
        .card()
    }

    private func numberCircle(_ number: Int, done: Bool) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(done ? Theme.onGreen : Theme.muted)
            .frame(width: 28, height: 28)
            .background(done ? Theme.green : Theme.card2)
            .clipShape(Circle())
    }

    private func todayRow(number: Int, set: PerformedSet) -> some View {
        HStack(spacing: 12) {
            numberCircle(number, done: true)
            (Text("\(Format.number(set.weightKg)) kg ").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                + Text("× \(set.reps) reps").font(.system(size: 14)).foregroundColor(Theme.muted))
            if set.isDeload { Pill(text: "Deload", tone: .amber) }
            Spacer()
            Button {
                if vm.deleteSet(id: set.id) { session.didChange() }
            } label: {
                Image(systemName: "trash").font(.system(size: 14)).foregroundColor(Theme.red)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Delete set \(number)")
            .accessibilityIdentifier("delete-set-\(number)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-set-\(number)")
    }

    private func emptyRow(number: Int) -> some View {
        Button { showingAddSet = true } label: {
            HStack(spacing: 12) {
                numberCircle(number, done: false)
                Text(vm.emptySlotText).font(.system(size: 15)).foregroundColor(Theme.muted)
                Spacer()
                Text("tap to log").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("empty-set-\(number)")
    }
}

private struct DetailTrendPill: View {
    let badge: ExerciseDetailViewModel.TrendBadge

    var body: some View {
        switch badge.tone {
        case .green: Pill(text: badge.text, tone: .green)
        case .amber: Pill(text: badge.text, tone: .amber)
        case .red: Pill(text: badge.text, tone: .red)
        case .grey: Pill(text: badge.text, tone: .grey)
        }
    }
}
