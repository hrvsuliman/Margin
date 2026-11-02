import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

enum TextImportError: LocalizedError {
    case unsupported(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .unsupported(let name):
            "„\(name)“ kann nicht gelesen werden. Word-Dateien (.docx) und Pages kann iOS nicht direkt öffnen – exportiere sie als PDF."
        case .noText:
            "In dieser Datei wurde kein Text gefunden."
        }
    }
}

/// Gets plain text out of files and photos, entirely on the device.
/// Text PDFs are read directly; scanned PDFs and photos go through Apple's
/// text recognition (Vision), which supports German.
enum TextImport {
    static let supportedTypes: [UTType] = [.pdf, .plainText, .utf8PlainText, .rtf, .image, UTType("net.daringfireball.markdown") ?? .plainText]

    static func text(from url: URL) async throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let text: String
        if type.conforms(to: .pdf) {
            text = try await pdfText(url)
        } else if type.conforms(to: .image) {
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw TextImportError.noText }
            text = try await recognizeText(in: image)
        } else if type.conforms(to: .rtf) {
            let attributed = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                    documentAttributes: nil)
            text = attributed.string
        } else if type.conforms(to: .text) || ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) {
            text = try String(contentsOf: url, encoding: .utf8)
        } else {
            throw TextImportError.unsupported(url.lastPathComponent)
        }
        let cleaned = clean(text)
        guard !cleaned.isEmpty else { throw TextImportError.noText }
        return cleaned
    }

    static func text(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw TextImportError.noText }
        let cleaned = clean(try await recognizeText(in: cgImage))
        guard !cleaned.isEmpty else { throw TextImportError.noText }
        return cleaned
    }

    private static func pdfText(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw TextImportError.unsupported(url.lastPathComponent) }
        let embedded = document.string ?? ""
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
            return embedded
        }
        // No text layer (a scan): recognise the first pages.
        var pages: [String] = []
        for index in 0..<min(document.pageCount, 20) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2200 / max(bounds.width, bounds.height, 1)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if let cgImage = image.cgImage {
                pages.append(try await recognizeText(in: cgImage))
            }
        }
        return pages.joined(separator: "\n\n")
    }

    static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["de-DE", "en-US"]
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "
"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Joins hyphenated line breaks and collapses runs of empty lines.
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "-\n(?=[a-zäöüß])", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
