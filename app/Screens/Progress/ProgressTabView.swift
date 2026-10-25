import FitnessCore
import SwiftUI

struct ProgressTabView: View {
    @EnvironmentObject private var services: Services

    var body: some View {
        // A new database means new services, so the view model must be rebuilt with them.
        ProgressScreen(services: services).id(ObjectIdentifier(services))
    }
}

private struct ProgressScreen: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ProgressViewModel
    @State private var addingSite = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    init(services: Services) {
        _model = StateObject(wrappedValue: ProgressViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    BodyHeader(caption: "Tap a ring to change current or target", title: "Progress")
                    if let loadError = model.loadError {
                        Text(loadError).font(.system(size: 13)).foregroundColor(Theme.red).card()
                    }
                    ringGrid
                    Button("+ Add a body site") { addingSite = true }
                        .buttonStyle(PrimaryButtonStyle(ghost: true))
                        .font(.system(size: 14))
                        .accessibilityIdentifier("add-site-button")
                    ProgressVolumeSection(model: model)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .screenBackground()
            .navigationTitle("Progress")
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: session.revision) { model.load() }
        .sheet(isPresented: $addingSite) {
            ProgressAddSiteSheet(model: model, onSaved: { session.didChange() })
        }
    }

    @ViewBuilder
    private var ringGrid: some View {
        if model.rings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No body sites yet").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                Text("Add a site with a first reading and a target to see how far you have left to go.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            .card()
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.rings) { ring in
                    NavigationLink {
                        MeasurementDetailView(site: ring.site)
                    } label: {
                        ProgressRingCard(ring: ring)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("measurement-ring-\(ring.site)")
                }
            }
        }
    }
}

private struct ProgressRingCard: View {
    let ring: MeasurementProgress

    var body: some View {
        HStack(spacing: 10) {
            RingView(progress: ring.fraction, size: 46, lineWidth: 5, color: MeasurementText.ringColor(ring.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(ring.site).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text).lineLimit(2)
                Text("\(MeasurementText.inches(ring.current)) → \(MeasurementText.inches(ring.target)) in")
                    .font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                Text(MeasurementText.statusLine(ring.status))
                    .font(.system(size: 11)).foregroundColor(MeasurementText.color(ring.status))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct ProgressAddSiteSheet: View {
    let model: ProgressViewModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var reading = ""
    @State private var target = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BodyField(label: "Name", text: $name, identifier: "site-name-field", keyboard: .default)
                    BodyField(label: "First reading (today)", text: $reading, unit: "in", identifier: "site-reading-field")
                    BodyField(label: "Target", text: $target, unit: "in", identifier: "site-target-field")
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Add a body site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).accessibilityIdentifier("sheet-save-button")
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        do {
            try model.addSite(nameText: name, firstReadingText: reading, targetText: target)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
