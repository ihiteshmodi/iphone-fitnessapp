import FitnessCore
import SwiftUI

struct WorkoutDayScreen: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var vm: WorkoutViewModel
    @AppStorage("selectedDayId") private var storedDayId = 0
    @State private var showingEditor = false

    init(services: Services) {
        _vm = StateObject(wrappedValue: WorkoutViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    WorkoutDayPicker(days: vm.days, selectedId: vm.selectedDayId, onSelect: select, onAdd: addDay)
                    if vm.workout != nil {
                        WorkoutHeroCard(vm: vm)
                        if vm.exercises.isEmpty {
                            emptyState
                        } else {
                            ForEach(vm.exercises) { exercise in
                                if let dayId = vm.selectedDayId {
                                    NavigationLink(value: WorkoutExerciseRoute(exerciseId: exercise.exerciseId, dayId: dayId)) {
                                        WorkoutExerciseCard(vm: vm, exercise: exercise)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("exercise-card-\(exercise.name)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle(vm.dayLabel.isEmpty ? "Workout" : vm.dayLabel)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutExerciseRoute.self) { route in
                ExerciseDetailView(exerciseId: route.exerciseId, dayId: route.dayId)
            }
        }
        .task(id: session.revision) { vm.reload(preferredDayId: storedDayId) }
        .sheet(isPresented: $showingEditor, onDismiss: { session.didChange() }) {
            if let dayId = vm.selectedDayId {
                NavigationStack { EditPlanView(focusDayId: dayId) }
            }
        }
        .errorAlert($vm.errorMessage)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.dateCaption).font(.system(size: 13)).foregroundColor(Theme.muted)
                Text("Workout").font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
            }
            Spacer()
            if vm.selectedDayId != nil {
                Button("Edit day") { showingEditor = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .padding(.top, 18)
                    .accessibilityIdentifier("edit-day-button")
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell").font(.system(size: 30)).foregroundColor(Theme.muted)
            Text("No exercises on this day yet").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
            Text("Add exercises to build this workout.").font(.system(size: 13)).foregroundColor(Theme.muted)
            Button("Add exercises") { showingEditor = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
                .accessibilityIdentifier("add-exercises-button")
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }

    private func select(_ dayId: Int) {
        storedDayId = dayId
        vm.reload(preferredDayId: dayId)
    }

    private func addDay() {
        guard let id = vm.addDay() else { return }
        storedDayId = id
        session.didChange()
    }
}

private struct WorkoutDayPicker: View {
    let days: [PlanDay]
    let selectedId: Int?
    let onSelect: (Int) -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(days) { day in
                            Button { onSelect(day.id) } label: {
                                Text(day.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(day.id == selectedId ? Theme.onGreen : Theme.muted)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(day.id == selectedId ? Theme.green : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .id(day.id)
                            .accessibilityIdentifier("day-\(day.position)")
                        }
                    }
                    .padding(4)
                }
                .background(Theme.card)
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .clipShape(Capsule())
                .onChange(of: selectedId) { id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.green)
                    .frame(width: 42, height: 42)
                    .background(Theme.card)
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Add day")
            .accessibilityIdentifier("add-day-button")
        }
    }
}

private struct WorkoutHeroCard: View {
    @ObservedObject var vm: WorkoutViewModel

    var body: some View {
        HStack(spacing: 16) {
            RingView(progress: vm.ringProgress, size: 92, lineWidth: 9, label: vm.ringLabel, subLabel: "done")
            VStack(alignment: .leading, spacing: 4) {
                if vm.hasTitle { SectionLabel(vm.dayLabel) }
                Text(vm.heroTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 18) {
                    stat("\(vm.exercises.count)", "exercises")
                    stat("\(vm.totalSets)", "sets")
                    stat("\(vm.toProgressCount)", "to progress", color: Theme.green)
                }
                .padding(.top, 4)
            }
        }
        .card(padding: 16)
    }

    private func stat(_ value: String, _ caption: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(color)
            Text(caption).font(.system(size: 10)).foregroundColor(Theme.muted)
        }
    }
}

private struct WorkoutExerciseCard: View {
    @ObservedObject var vm: WorkoutViewModel
    let exercise: WorkoutExercise

    var body: some View {
        HStack(spacing: 8) {
            RingView(progress: vm.ringProgress(exercise), size: 40, lineWidth: 5, label: vm.ringLabel(exercise))
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(vm.meta(exercise)).font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            SparklineView(values: exercise.sparkline, width: 38, height: 26)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(exercise.workingWeight.map { Format.number($0) } ?? "–")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.text)
                    if exercise.workingWeight != nil {
                        Text("kg").font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
                WorkoutBadgePill(badge: vm.badge(exercise))
            }
            .fixedSize()
        }
        .card(padding: 12)
        .contentShape(Rectangle())
    }
}

private struct WorkoutBadgePill: View {
    let badge: WorkoutViewModel.Badge

    var body: some View {
        switch badge.tone {
        case .green: Pill(text: badge.text, tone: .green)
        case .amber: Pill(text: badge.text, tone: .amber)
        case .grey: Pill(text: badge.text, tone: .grey)
        }
    }
}
