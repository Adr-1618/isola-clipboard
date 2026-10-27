import AppKit
import Foundation
import UniformTypeIdentifiers

@main
struct ClipboardHistorySmoke {
    @MainActor
    static func main() throws {
        let suiteName = "IsolaClipboard.SmokeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        try expect(preferences.closeDelaySeconds == 2 && preferences.closeOnOutsideClick, "default dismissal preferences are incorrect")
        let history = ClipboardHistory(pasteboard: .general, preferences: preferences)
        var addedCount = 0
        history.onNewItem = { addedCount += 1 }

        history.ingest(.text("test item 1"))
        history.ingest(.text("test item 2"))
        history.ingest(.url(URL(string: "https://example.test/isola")!))
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        history.ingest(.image(image))

        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("IsolaClipboardSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let testFile = testDirectory.appendingPathComponent("AnnualReview2026FinalApprovalDocument.docx")
        try Data("test file".utf8).write(to: testFile)
        history.ingest(.file(testFile))
        history.ingest(.text("test item 5"))

        try expect(history.entries.count == 5, "five distinct copies did not produce five entries")
        try expect(history.entries.first?.title == "test item 5", "newest item is not first")
        try expect(history.entries.contains(where: { $0.title == "example.test" }), "URL did not produce a compact history entry")
        try expect(history.entries.contains(where: { $0.title == "AnnualReview2026FinalApprovalDocument.docx" }), "file name or extension was not retained")
        let fileEntry = history.entries.first(where: { $0.title == "AnnualReview2026FinalApprovalDocument.docx" })!
        try expect(fileEntry.makeItemProvider().registeredTypeIdentifiers.contains(UTType.fileURL.identifier), "file drag provider did not export a native file URL")
        let wrappedFilename = fileEntry.displayTitle(maxCharactersPerLine: 20, maxLines: 3)
        try expect(wrappedFilename.contains("\n"), "long filename was not wrapped onto multiple visible lines")
        try expect(wrappedFilename.replacingOccurrences(of: "\n", with: "") == fileEntry.title, "wrapped filename label changed the original filename")
        let nativeDragWriter = fileEntry.makePasteboardWriter()
        try expect((nativeDragWriter as? NSURL)?.path == testFile.path, "AppKit drag writer changed the source file path")
        let nativeDragTypes = nativeDragWriter.writableTypes(for: .general)
        try expect(nativeDragTypes.contains(.fileURL), "AppKit drag writer did not export a file URL")
        try expect(FileManager.default.fileExists(atPath: testFile.path), "creating the drag writer removed or moved the source file")
        try expect(ClipboardEntry(content: .text("drag text")).makePasteboardWriter().writableTypes(for: .general).contains(.string), "text drag writer did not advertise plain text")
        try expect(ClipboardEntry(content: .url(URL(string: "https://example.test/drag")!)).makePasteboardWriter().writableTypes(for: .general).contains(.URL), "URL drag writer did not advertise a URL")
        let imageWriter = ClipboardEntry(content: .image(image)).makePasteboardWriter()
        let imageDragTypes = imageWriter.writableTypes(for: .general)
        try expect(imageDragTypes.contains(.fileURL), "image drag writer did not export a file URL for Finder")
        try expect(imageDragTypes.contains(.png), "image drag writer did not advertise PNG data")
        try expect(imageDragTypes.contains(.tiff), "image drag writer did not advertise TIFF image data")
        if let imageItem = imageWriter as? NSPasteboardItem,
           let fileURLString = imageItem.string(forType: .fileURL),
           let exportURL = URL(string: fileURLString) {
            try expect(FileManager.default.fileExists(atPath: exportURL.path), "image drag export file was not created")
            try expect(imageItem.data(forType: .png) != nil, "image drag writer lost its PNG representation")
            try? FileManager.default.removeItem(at: exportURL)
        } else {
            throw NSError(domain: "IsolaClipboardSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "image drag writer did not provide a readable file URL"])
        }
        try expect(history.entries.contains(where: { $0.subtitle == "Immagine" }), "image did not produce a thumbnail entry")

        history.ingest(.text("test item 6"))
        try expect(history.entries.count == 5, "history exceeded its five item limit")
        try expect(history.entries.first?.title == "test item 6", "sixth item is not first")
        try expect(!history.entries.contains(where: { $0.title == "test item 1" }), "sixth item did not replace the oldest item")

        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        history.ingest(.text("hidden test secret"), sourceTypes: [.string, concealed])
        history.ingest(.text("temporary test content"), sourceTypes: [.string, transient])
        try expect(history.entries.first?.title == "test item 6", "concealed or temporary content was not ignored")
        try expect(addedCount == 7, "protected contents triggered a new item callback")

        preferences.maxItems = 3
        preferences.showMenuBarIcon = false
        preferences.theme = .dark
        preferences.animationsEnabled = false
        preferences.shortcutKeyCode = 49
        preferences.shortcutModifiers = 768
        preferences.closeDelaySeconds = 7
        preferences.closeOnOutsideClick = false
        history.ingest(.text("test item 7"))
        history.ingest(.text("test item 8"))
        history.ingest(.text("test item 9"))
        try expect(history.entries.count == 3, "configured history size was not applied")
        try expect(history.entries.first?.title == "test item 9", "configured history has the wrong order")
        try expect(addedCount == 10, "new item callback count is incorrect")

        let reloadedPreferences = AppPreferences(defaults: defaults)
        try expect(!reloadedPreferences.showMenuBarIcon, "menu bar preference was not persisted")
        try expect(reloadedPreferences.theme == .dark && !reloadedPreferences.animationsEnabled, "appearance settings were not persisted")
        try expect(reloadedPreferences.shortcutKeyCode == 49 && reloadedPreferences.shortcutModifiers == 768, "shortcut settings were not persisted")
        try expect(reloadedPreferences.closeDelaySeconds == 7 && !reloadedPreferences.closeOnOutsideClick, "dismissal settings were not persisted")

        print("PASS: text, URL, image, and file history entries")
        print("PASS: five item limit and sixth item eviction")
        print("PASS: concealed and transient content filters")
        print("PASS: configurable history size and insertion callback")
        print("PASS: native file URL drag provider preserves the original filename")
        print("PASS: filename line-break opportunities preserve the original visible name")
        print("PASS: AppKit drag writer preserves the source path and advertises file URL")
        print("PASS: text, URL, and image drag writers advertise native pasteboard formats")
        print("PASS: creating a file drag writer leaves the original file in place")
        print("PASS: menu bar, appearance, and shortcut preferences persist")
        print("PASS: dismissal timeout and outside-click preferences persist")
    }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "IsolaClipboardSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
