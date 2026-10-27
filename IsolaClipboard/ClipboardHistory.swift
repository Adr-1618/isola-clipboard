import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()

    @Published private(set) var entries: [ClipboardEntry] = []
    var onNewItem: (() -> Void)?
    private let pasteboard: NSPasteboard
    private let preferences: AppPreferences
    private var lastChangeCount = -1
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general, preferences: AppPreferences? = nil) {
        self.pasteboard = pasteboard
        self.preferences = preferences ?? .shared
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = -1
        checkForChanges()
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForChanges() }
        }
    }

    func clear() {
        entries.removeAll()
    }

    func trim(to maximumCount: Int) {
        let maximumCount = min(max(maximumCount, 1), 5)
        if entries.count > maximumCount {
            entries.removeLast(entries.count - maximumCount)
        }
    }

    func copyToPasteboard(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        switch entry.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .url(let url):
            pasteboard.writeObjects([url as NSURL])
        case .image(let image):
            pasteboard.writeObjects([image])
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        }
        lastChangeCount = pasteboard.changeCount
    }

    func checkForChanges() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let pasteboardTypes = pasteboard.pasteboardItems?.flatMap(\.types) ?? []

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            for url in fileURLs.reversed() { ingest(.file(url), sourceTypes: pasteboardTypes) }
            return
        }

        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            ingest(.image(image), sourceTypes: pasteboardTypes)
            return
        }

        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           ["http", "https", "mailto", "ftp"].contains(url.scheme?.lowercased() ?? "") {
            ingest(.url(url), sourceTypes: pasteboardTypes)
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            if let url = URL(string: text), ["http", "https", "mailto", "ftp"].contains(url.scheme?.lowercased() ?? "") {
                ingest(.url(url), sourceTypes: pasteboardTypes)
            } else {
                ingest(.text(text), sourceTypes: pasteboardTypes)
            }
        }
    }

    func ingest(_ content: ClipboardEntry.Content, sourceTypes: [NSPasteboard.PasteboardType] = []) {
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        if preferences.ignoreConcealed && sourceTypes.contains(concealedType) { return }
        if preferences.ignoreTransient && sourceTypes.contains(transientType) { return }

        insert(content)
    }

    private func insert(_ content: ClipboardEntry.Content) {
        let entry = ClipboardEntry(content: content)
        entries.removeAll { $0.fingerprint == entry.fingerprint }
        entries.insert(entry, at: 0)
        trim(to: preferences.maxItems)
        onNewItem?()
    }
}

@MainActor
struct ClipboardEntry: Identifiable {
    enum Content {
        case text(String)
        case url(URL)
        case image(NSImage)
        case file(URL)
    }

    let id = UUID()
    let content: Content
    let fingerprint: String

    init(content: Content) {
        self.content = content
        switch content {
        case .text(let text): fingerprint = "text:" + text
        case .url(let url): fingerprint = "url:" + url.absoluteString
        case .image(let image): fingerprint = "image:\(image.size.width)x\(image.size.height):\(image.tiffRepresentation?.hashValue ?? 0)"
        case .file(let url): fingerprint = "file:" + url.standardizedFileURL.absoluteString
        }
    }

    var title: String {
        switch content {
        case .text(let text):
            let compact = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            return String(compact.prefix(100))
        case .url(let url): return url.host ?? url.absoluteString
        case .image(let image): return "Immagine · \(Int(image.size.width)) × \(Int(image.size.height))"
        case .file(let url): return url.lastPathComponent
        }
    }

    /// Inserts explicit line breaks for the compact tile label without changing the
    /// original title used by accessibility, tooltips, or drag-and-drop.
    func displayTitle(maxCharactersPerLine: Int, maxLines: Int) -> String {
        let characters = Array(title)
        let lineCapacity = max(1, maxCharactersPerLine)
        let lineLimit = max(1, maxLines)
        guard characters.count > lineCapacity else { return title }

        var lines: [String] = []
        var offset = 0
        while offset < characters.count && lines.count < lineLimit {
            let remaining = characters.count - offset
            if remaining <= lineCapacity {
                lines.append(String(characters[offset...]))
                offset = characters.count
                break
            }

            let upperBound = offset + lineCapacity
            let searchRange = offset..<upperBound
            let naturalBreak = characters[searchRange].lastIndex(where: {
                $0.isWhitespace || "_-.,;".contains($0)
            })
            let splitIndex = naturalBreak.flatMap { $0 > offset + lineCapacity / 2 ? $0 + 1 : nil } ?? upperBound
            lines.append(String(characters[offset..<splitIndex]))
            offset = splitIndex
        }

        if offset < characters.count, !lines.isEmpty {
            lines[lines.count - 1] = String(lines[lines.count - 1].dropLast()) + "…"
        }
        return lines.joined(separator: "\n")
    }

    var subtitle: String {
        switch content {
        case .text(let text): return text.count > 100 ? "Testo · \(text.count) caratteri" : "Testo"
        case .url(let url): return url.absoluteString
        case .image: return "Immagine"
        case .file(let url): return url.deletingLastPathComponent().path
        }
    }

    var previewImage: NSImage? {
        switch content {
        case .image(let image): return image
        case .file(let url): return NSWorkspace.shared.icon(forFile: url.path)
        default: return nil
        }
    }

    var symbol: String {
        switch content {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var dragContentType: String {
        switch content {
        case .text: return "text"
        case .url: return "url"
        case .image: return "image"
        case .file: return "file"
        }
    }

    func makeItemProvider() -> NSItemProvider {
        switch content {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .url(let url):
            return NSItemProvider(object: url as NSURL)
        case .file(let url):
            // Export the original file URL as a file URL so Finder keeps the source name and extension.
            return NSItemProvider(object: url as NSURL)
        case .image(let image):
            let provider = NSItemProvider()
            let pngData = image.tiffRepresentation
                .flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                guard let pngData else {
                    completion(nil, CocoaError(.fileReadUnknown))
                    return nil
                }
                completion(pngData, nil)
                return nil
            }
            return provider
        }
    }

    func makePasteboardWriter() -> NSPasteboardWriting {
        switch content {
        case .text(let text): text as NSString
        case .url(let url), .file(let url): url as NSURL
        case .image(let image):
            guard let pngData = image.tiffRepresentation
                .flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
            else {
                return image
            }

            // Finder accepts image files as file URLs when dropping into folders.
            // Keep native PNG/TIFF representations on the same item for image editors.
            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("IsolaClipboard-\(UUID().uuidString).png")
            do {
                try pngData.write(to: exportURL, options: .atomic)
            } catch {
                return image
            }

            let item = NSPasteboardItem()
            item.setString(exportURL.absoluteString, forType: .fileURL)
            item.setData(pngData, forType: .png)
            if let tiffData = image.tiffRepresentation {
                item.setData(tiffData, forType: .tiff)
            }
            return item
        }
    }

    var dragPreview: NSImage {
        previewImage ?? NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(size: NSSize(width: 64, height: 64))
    }
}
