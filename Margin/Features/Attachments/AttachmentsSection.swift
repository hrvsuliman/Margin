import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A list section showing the files attached to a task or subject,
/// with import from the Files app or the photo library and Quick Look preview.
struct AttachmentsSection: View {
    enum Owner {
        case task(SchoolTask)
        case subject(SchoolSubject)
    }

    @Environment(\.modelContext) private var context
    let owner: Owner
    var title = "Anhänge"

    @State private var showImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    private var attachments: [Attachment] {
        let list: [Attachment]
        switch owner {
        case .task(let task): list = task.attachments ?? []
        case .subject(let subject): list = subject.attachments ?? []
        }
        return list.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Section(title) {
            ForEach(attachments) { attachment in
                Button {
                    previewURL = AttachmentStore.url(for: attachment)
                } label: {
                    row(attachment)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        AttachmentStore.delete(attachment, context: context)
                        context.commit()
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }

            Menu {
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Foto aufnehmen", systemImage: "camera")
                    }
                }
                Button {
                    showPhotos = true
                } label: {
                    Label("Aus Fotos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Aus Dateien", systemImage: "folder")
                }
            } label: {
                Label("Anhang hinzufügen", systemImage: "paperclip")
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let jpeg = image.jpegForStorage() {
                        let stamp = Fmt.date(.now).replacingOccurrences(of: ".", with: "-")
                        add { try AttachmentStore.store(jpeg, fileName: "Foto \(stamp).jpg") }
                    }
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls { add { try AttachmentStore.importFile(at: url) } }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: photoItems) {
                let items = photoItems
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await importPhotos(items) }
            }
            .quickLookPreview($previewURL)
            .alert("Anhang konnte nicht hinzugefügt werden", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func row(_ attachment: Attachment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: attachment.fileName))
                .font(.title3)
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(AttachmentStore.sizeText(attachment.byteCount)) · \(Fmt.date(attachment.createdAt))")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private func symbol(for fileName: String) -> String {
        let type = UTType(filenameExtension: (fileName as NSString).pathExtension)
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        if type?.conforms(to: .image) == true { return "photo" }
        if type?.conforms(to: .presentation) == true { return "rectangle.on.rectangle" }
        if type?.conforms(to: .spreadsheet) == true { return "tablecells" }
        return "doc"
    }

    private func add(_ make: () throws -> Attachment) {
        do {
            let attachment = try make()
            context.insert(attachment)
            switch owner {
            case .task(let task): attachment.task = task
            case .subject(let subject): attachment.subject = subject
            }
            context.commit()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let stamp = Fmt.date(.now).replacingOccurrences(of: ".", with: "-")
                let name = items.count > 1 ? "Foto \(stamp) (\(index + 1)).\(ext)" : "Foto \(stamp).\(ext)"
                add { try AttachmentStore.store(data, fileName: name) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
