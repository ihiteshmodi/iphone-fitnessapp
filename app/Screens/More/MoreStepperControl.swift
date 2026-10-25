import SwiftUI

/// "−  value  +" control from the mockups, used for multipliers, sets and rep ranges.
struct MoreStepperControl: View {
    let title: String
    let value: String
    var canDecrement = true
    var canIncrement = true
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: canDecrement, label: "Decrease \(title)", action: onDecrement)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.text)
                .frame(minWidth: 44)
                .accessibilityIdentifier("stepper-value-\(title)")
            stepButton("plus", enabled: canIncrement, label: "Increase \(title)", action: onIncrement)
        }
        .background(Theme.card2)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(enabled ? Theme.green : Theme.muted.opacity(0.5))
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// A label on the left and any control on the right, with the divider line used by the mockup's list cards.
struct MoreRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15)).foregroundColor(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
    }
}
