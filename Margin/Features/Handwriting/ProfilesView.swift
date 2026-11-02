import SwiftData
import SwiftUI

/// A running capture session (for `fullScreenCover(item:)`).
struct CaptureSession: Identifiable {
    let id = UUID()
    let profile: HandwritingProfile
    let items: [CaptureItem]
    let title: String

    /// Everything not written yet, then the sample word if spacing wasn't measured.
    @MainActor
    static func missing(for profile: HandwritingProfile) -> CaptureSession {
        let have = profile.capturedCharacters
        var items = HandwritingCharset.all.filter { !have.contains($0) }.map { CaptureItem.character($0) }
        if !profile.spacingMeasured { items.append(.sampleWord(HandwritingCharset.sampleWord)) }
        return CaptureSession(profile: profile, items: items, title: "Zeichen schreiben")
    }

    /// Two extra versions of the most common letters.
    @MainActor
    static func variants(for profile: HandwritingProfile) -> CaptureSession {
        let items = HandwritingCharset.variantLetters.flatMap { [CaptureItem.character($0), .character($0)] }
        return CaptureSession(profile: profile, items: items, title: "Varianten")
    }
}

struct ProfilesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HandwritingProfile.createdAt) private var profiles: [HandwritingProfile]
    @State private var opened: HandwritingProfile?
    @State private var capture: CaptureSession?
    @State private var pendingDelete: HandwritingProfile?
    @State private var penScan: HandwritingProfile?

    var body: some View {
        List {
            if profiles.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "signature",
                        title: "Deine Handschrift",
                        message: "Du füllst eine Vorlage mit deinem eigenen Stift aus und scannst sie. Margin setzt daraus Texte in deiner Schrift. Alles bleibt auf diesem iPhone.",
                        actionTitle: "Jetzt einrichten",
                        action: { createProfile(startScan: true) }
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(profiles) { profile in
                        NavigationLink {
                            ProfileDetailView(profile: profile)
                        } label: {
                            ProfileRow(profile: profile)
                        }
                    }
                    .onDelete { offsets in
                        pendingDelete = offsets.first.map { profiles[$0] }
                    }
                } footer: {
                    Text("Handschriftproben bleiben auf diesem iPhone und werden nirgendwohin gesendet.")
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Handschrift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createProfile(startScan: true)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neue Handschrift")
            }
        }
        .navigationDestination(item: $opened) { profile in
            ProfileDetailView(profile: profile)
        }
        .fullScreenCover(item: $capture) { session in
            CaptureFlowView(profile: session.profile, items: session.items, title: session.title)
        }
        .sheet(item: $penScan) { profile in
            NavigationStack { PenScanView(profile: profile) }
                .tint(Palette.marginRed)
        }
        .confirmationDialog("Handschrift löschen?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { profile in
            Button("Löschen", role: .destructive) {
                context.delete(profile)
                context.commit()
            }
        } message: { _ in
            Text("Alle Schriftproben dieses Profils werden gelöscht. Notizen bleiben erhalten und nutzen dann ein anderes Profil.")
        }
    }

    private func createProfile(startScan: Bool) {
        let profile = HandwritingProfile(name: profiles.isEmpty ? "Meine Handschrift" : "Handschrift \(profiles.count + 1)")
        profile.isDefault = profiles.isEmpty
        context.insert(profile)
        context.commit()
        opened = profile
        if startScan {
            Deferred.afterDismiss { penScan = profile }
        }
    }
}

private struct ProfileRow: View {
    let profile: HandwritingProfile

    var body: some View {
        let count = profile.capturedCharacters.intersection(HandwritingCharset.all).count
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(profile.name).foregroundStyle(Palette.ink)
                if profile.isDefault {
                    Text("Standard")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.marginRed)
                }
            }
            Text("\(count) von \(HandwritingCharset.all.count) Zeichen · \(profile.glyphs?.count ?? 0) Proben")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}
