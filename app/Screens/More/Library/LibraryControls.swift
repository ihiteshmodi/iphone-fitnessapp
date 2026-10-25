import SwiftUI

struct LibrarySearchField: View {
    @Binding var text: String
    var prompt = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.muted))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundColor(Theme.text)
                .accessibilityIdentifier("library-search-field")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// One chip per muscle plus "All"; `selection == nil` means All.
struct LibraryMuscleChips: View {
    let muscles: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LibraryChip(title: "All", isOn: selection == nil) { selection = nil }
                ForEach(muscles, id: \.self) { muscle in
                    LibraryChip(title: muscle, isOn: selection?.caseInsensitiveCompare(muscle) == .orderedSame) { selection = muscle }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

struct LibraryChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isOn ? Theme.onGreen : Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Theme.green : Theme.card)
                .overlay(Capsule().stroke(isOn ? Color.clear : Theme.line))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
