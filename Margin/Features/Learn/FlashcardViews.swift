import SwiftData
import SwiftUI

/// Which cards a deck shows.
enum CardScope: Hashable {
    case all
    case subject(UUID?)
    case topic(UUID)

    func contains(_ card: Flashcard) -> Bool {
        switch self {
        case .all: true
        case .subject(let id): card.subjectUID == id
        case .topic(let id): card.topicUID == id
        }
    }
}

/// All cards of one subject (or topic): browse, add, learn.
struct FlashcardDeckView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Flashcard.createdAt) private var allCards: [Flashcard]
    let scope: CardScope
    let title: String

    @State private var editing: Flashcard?
    @State private var creating = false
    @State private var review: ReviewRequest?

    private var cards: [Flashcard] { allCards.filter(scope.contains) }
    private var due: [Flashcard] { cards.filter { $0.due <= .now } }

    var body: some View {
        List {
            Section {
                Button {
                    review = ReviewRequest(cards: due.isEmpty ? cards.shuffled() : due)
                } label: {
                    HStack {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(due.isEmpty ? "Alle üben" : "\(due.count) fällige lernen")
                                .font(.headline)
                            Text(due.isEmpty ? "Nichts fällig – trotzdem durchgehen" : "Wiederholung im richtigen Abstand")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
                .disabled(cards.isEmpty)
            }
            .marginRow()

            Section {
                if cards.isEmpty {
                    Text("Noch keine Karten. Lege welche mit + an – oder schreib in einer Notiz Zeilen wie „Mitose :: Zellteilung, bei der …“, daraus entstehen automatisch Karten.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(cards) { card in
                    Button {
                        editing = card
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.front).foregroundStyle(Palette.ink).lineLimit(2)
                            Text(card.back).font(.caption).foregroundStyle(Palette.secondaryInk).lineLimit(2)
                            Text(dueText(card)).font(.caption2).foregroundStyle(Palette.faintInk)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(cards[index]) }
                    try? context.save()
                }
            } header: {
                SectionTitle("Karten", trailing: "\(cards.count)")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neue Karte")
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { FlashcardEditor(card: nil, scope: scope) }
                .tint(Palette.marginRed)
        }
        .sheet(item: $editing) { card in
            NavigationStack { FlashcardEditor(card: card, scope: scope) }
                .tint(Palette.marginRed)
        }
        .fullScreenCover(item: $review) { request in
            FlashcardReviewView(cards: request.cards)
        }
    }

    private func dueText(_ card: Flashcard) -> String {
        if card.lastReviewed == nil { return "neu" }
        if card.due <= .now { return "fällig" }
        return "nächste Wiederholung \(Fmt.relativeDay(card.due))"
    }
}

struct ReviewRequest: Identifiable {
    let id = UUID()
    let cards: [Flashcard]
}

struct FlashcardEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    let card: Flashcard?

    @State private var front: String
    @State private var back: String
    @State private var subjectUID: UUID?
    @State private var topicUID: UUID?

    init(card: Flashcard?, scope: CardScope) {
        self.card = card
        _front = State(initialValue: card?.front ?? "")
        _back = State(initialValue: card?.back ?? "")
        var subject = card?.subjectUID
        var topic = card?.topicUID
        if card == nil {
            switch scope {
            case .subject(let id): subject = id
            case .topic(let id): topic = id
            case .all: break
            }
        }
        _subjectUID = State(initialValue: subject)
        _topicUID = State(initialValue: topic)
    }

    private var subject: SchoolSubject? { subjectUID.flatMap { id in subjects.first { $0.uid == id } } }

    var body: some View {
        Form {
            Section("Vorderseite") {
                TextField("Begriff oder Frage", text: $front, axis: .vertical)
                    .font(.body.weight(.medium))
            }
            .marginRow()
            Section("Rückseite") {
                TextField("Erklärung oder Antwort", text: $back, axis: .vertical)
                    .lineLimit(2...8)
            }
            .marginRow()
            Section {
                Picker("Fach", selection: $subjectUID) {
                    Text("Kein Fach").tag(nil as UUID?)
                    ForEach(subjects) { Text($0.name).tag($0.uid as UUID?) }
                }
                if let subject, !(subject.topics ?? []).isEmpty {
                    Picker("Thema", selection: $topicUID) {
                        Text("Kein Thema").tag(nil as UUID?)
                        ForEach(TopicOutline.flatten(subject.rootTopics), id: \.topic.uid) { entry in
                            Text(String(repeating: "   ", count: entry.depth) + entry.topic.title).tag(entry.topic.uid as UUID?)
                        }
                    }
                }
            } footer: {
                if card?.noteUID != nil {
                    Text("Diese Karte stammt aus einer Notiz. Änderungen an der Zeile in der Notiz überschreiben sie.")
                }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(card == nil ? "Neue Karte" : "Karte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
                    .disabled(front.trimmingCharacters(in: .whitespaces).isEmpty || back.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let target = card ?? Flashcard(front: "", back: "")
        if card == nil { context.insert(target) }
        target.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        target.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        target.subjectUID = subjectUID
        target.topicUID = topicUID
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

/// Learning cards one by one, written on index cards in your handwriting.
struct FlashcardReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HandwritingProfile.createdAt) private var profiles: [HandwritingProfile]

    @State private var queue: [Flashcard]
    @State private var index = 0
    @State private var flipped = false
    @State private var font: HandwritingFont?
    /// First answer per card: true = known.
    @State private var firstAnswers: [UUID: Bool] = [:]
    @State private var finished = false

    init(cards: [Flashcard]) {
        _queue = State(initialValue: cards)
    }

    private var card: Flashcard? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                if finished || card == nil {
                    summary
                } else if let card {
                    reviewing(card)
                }
            }
            .navigationTitle(finished ? "Geschafft" : "\(min(index + 1, queue.count)) / \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Fertig" : "Beenden") {
                        if !finished { saveResults() }
                        dismiss()
                    }
                }
            }
        }
        .tint(Palette.marginRed)
        .task {
            let source = NoteRendering.defaultProfile(in: profiles).map { FontSource(profile: $0) } ?? .empty
            font = await Task.detached(priority: .userInitiated) { HandwritingFont(source: source, penRatio: 0.16) }.value
        }
    }

    private func reviewing(_ card: Flashcard) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                IndexCard(text: card.front, font: font)
                    .opacity(flipped ? 0 : 1)
                IndexCard(text: card.back, font: font)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .padding(.horizontal, 20)
            .onTapGesture { flip() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(flipped ? "Rückseite: \(card.back)" : "Vorderseite: \(card.front)")
            .accessibilityHint("Doppeltippen zum Umdrehen")
            .id(card.uid)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))

            Spacer()
            if flipped {
                HStack(spacing: 8) {
                    ForEach(ReviewGrade.allCases, id: \.self) { grade in
                        Button {
                            answer(grade, card: card)
                        } label: {
                            VStack(spacing: 2) {
                                Text(grade.title).font(.subheadline.weight(.semibold))
                                Text(intervalText(grade, card: card)).font(.caption2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .tint(grade == .again ? Palette.marginRed : Palette.ink)
                    }
                }
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button("Umdrehen", action: flip)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .foregroundStyle(Palette.paper)
            }
            Spacer().frame(height: 24)
        }
    }

    private var summary: some View {
        let known = firstAnswers.values.filter { $0 }.count
        return VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Palette.marginRed)
            Text("\(firstAnswers.count) Karten wiederholt")
                .font(.system(.title, design: .serif, weight: .semibold))
            Text(firstAnswers.isEmpty ? "" : "\(known) davon auf Anhieb gewusst")
                .foregroundStyle(Palette.secondaryInk)
            Text("Schwierige Karten kommen bald wieder, sichere erst in ein paar Tagen.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .onAppear { if !finished { finished = true; saveResults() } }
    }

    private func flip() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { flipped.toggle() }
        Haptics.tap()
    }

    private func intervalText(_ grade: ReviewGrade, card: Flashcard) -> String {
        let next = SpacedRepetition.review(LearningStore.schedule(of: card), grade: grade, now: .now)
        if grade == .again { return "gleich" }
        return next.intervalDays == 1 ? "1 Tag" : "\(next.intervalDays) Tage"
    }

    private func answer(_ grade: ReviewGrade, card: Flashcard) {
        if firstAnswers[card.uid] == nil { firstAnswers[card.uid] = grade != .again }
        LearningStore.apply(grade, to: card)
        LearningStore.markStudied(topicUID: card.topicUID, context: context)
        try? context.save()
        if grade == .again {
            queue.append(card) // once more at the end
        }
        if grade == .again { Haptics.warning() } else { Haptics.success() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            flipped = false
            index += 1
        }
        if index >= queue.count { finished = true; saveResults() }
    }

    /// One practice result per topic (or subject) for readiness and statistics.
    private func saveResults() {
        guard !firstAnswers.isEmpty else { return }
        var groups: [String: (topic: UUID?, subject: UUID?, known: Int, total: Int)] = [:]
        var seen: Set<UUID> = []
        for card in queue where firstAnswers[card.uid] != nil && seen.insert(card.uid).inserted {
            let key = card.topicUID?.uuidString ?? card.subjectUID?.uuidString ?? "none"
            var entry = groups[key] ?? (card.topicUID, card.subjectUID, 0, 0)
            entry.known += firstAnswers[card.uid] == true ? 1 : 0
            entry.total += 1
            groups[key] = entry
        }
        for entry in groups.values where entry.total > 0 {
            let result = PracticeResult(score: Double(entry.known) / Double(entry.total), kind: "cards")
            result.topicUID = entry.topic
            result.subjectUID = entry.subject
            context.insert(result)
        }
        try? context.save()
        firstAnswers = [:]
    }
}

/// An A7 index card (lined) with text in the user's handwriting.
struct IndexCard: View {
    let text: String
    let font: HandwritingFont?

    @State private var page: LaidOutPage?
    @State private var settings = IndexCard.cardSettings(for: "")

    static func cardSettings(for text: String) -> PageSettings {
        var spec = PageSettings()
        spec.pageSize = CGSize(width: PageSettings.mm(105), height: PageSettings.mm(74))
        spec.paper = .lined
        spec.lineSpacing = PageSettings.mm(7.5)
        spec.marginTop = PageSettings.mm(8)
        spec.marginBottom = PageSettings.mm(4)
        spec.marginLeft = PageSettings.mm(7)
        spec.marginRight = PageSettings.mm(7)
        spec.showHeader = false
        spec.showPageNumbers = false
        spec.showMarginLine = false
        spec.writingSize = text.count < 30 ? 1.25 : (text.count < 120 ? 1.05 : 0.85)
        return spec
    }

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                let scale = size.width / settings.pageSize.width
                cg.scaleBy(x: scale, y: scale)
                PageRenderer.draw(page, settings: settings, in: cg, includePaper: true)
                // Red header line like a real index card.
                cg.setStrokeColor(PageRenderer.marginColor.cgColor)
                cg.setLineWidth(0.8)
                cg.move(to: CGPoint(x: 0, y: settings.marginTop))
                cg.addLine(to: CGPoint(x: settings.pageSize.width, y: settings.marginTop))
                cg.strokePath()
            }
        }
        .aspectRatio(105 / 74, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .task(id: "\(text)-\(font.map { ObjectIdentifier($0).hashValue } ?? 0)") {
            guard let font else { return }
            let spec = Self.cardSettings(for: text)
            let content = NoteContent(title: "", header: "", body: text, seed: StableHash.of(text))
            let laidOut = await Task.detached(priority: .userInitiated) {
                NoteLayout.layout(content, settings: spec, font: font).first
            }.value
            settings = spec
            page = laidOut
        }
    }
}
