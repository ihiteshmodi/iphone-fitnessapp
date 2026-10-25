import SwiftUI

/// Three steppers (sets, min reps, max reps) as one block.
struct PlanRepSchemeEditor: View {
    @Binding var scheme: PlanRepScheme

    var body: some View {
        VStack(spacing: 0) {
            MoreRow(title: "Sets") {
                MoreStepperControl(title: "Sets", value: "\(scheme.sets)",
                                   canDecrement: scheme.sets > 1, canIncrement: scheme.sets < PlanRepScheme.maxSets,
                                   onDecrement: { scheme.changeSets(by: -1) }, onIncrement: { scheme.changeSets(by: 1) })
            }
            Divider().overlay(Theme.line)
            MoreRow(title: "Min reps") {
                MoreStepperControl(title: "Min reps", value: "\(scheme.minReps)",
                                   canDecrement: scheme.minReps > 0, canIncrement: scheme.minReps < PlanRepScheme.maxReps,
                                   onDecrement: { scheme.changeMinReps(by: -1) }, onIncrement: { scheme.changeMinReps(by: 1) })
            }
            Divider().overlay(Theme.line)
            MoreRow(title: "Max reps") {
                MoreStepperControl(title: "Max reps", value: "\(scheme.maxReps)",
                                   canDecrement: scheme.maxReps > 1, canIncrement: scheme.maxReps < PlanRepScheme.maxReps,
                                   onDecrement: { scheme.changeMaxReps(by: -1) }, onIncrement: { scheme.changeMaxReps(by: 1) })
            }
        }
    }
}
