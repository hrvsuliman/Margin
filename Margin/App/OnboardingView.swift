import SwiftUI

/// Three calm pages on first launch: what Margin is, where the data stays, how to start.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    private let pages = [
        Page(symbol: "pencil.and.outline",
             title: "Schule auf Papier, nur klüger",
             text: "Stundenplan, Aufgaben, Prüfungen und Notizen an einem Ort. Notizen erscheinen in deiner eigenen Handschrift."),
        Page(symbol: "lock",
             title: "Deine Daten bleiben bei dir",
             text: "Alles liegt auf deinem iPhone. Nur wenn du Claude, WebUntis oder den Kalender selbst einschaltest, wird etwas gesendet – und Margin sagt dir vorher, was."),
        Page(symbol: "list.bullet.rectangle",
             title: "So fängst du an",
             text: "1. Fächer anlegen\n2. Stundenplan eintragen oder WebUntis verbinden\n3. Handschrift einscannen (Notizen › Handschrift)\n4. Nächste Arbeit eintragen – Margin plant das Lernen."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(alignment: .leading, spacing: 18) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Palette.marginRed)
                        Text(item.title)
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: 520, alignment: .leading)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation(.easeInOut) { page += 1 }
                } else {
                    dismiss()
                }
                Haptics.tap()
            } label: {
                Text(page < pages.count - 1 ? "Weiter" : "Los geht's")
                    .font(.headline)
                    .frame(maxWidth: 420)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ink)
            .foregroundStyle(Palette.paper)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Palette.paper.ignoresSafeArea())
        .interactiveDismissDisabled(page < pages.count - 1)
    }
}
