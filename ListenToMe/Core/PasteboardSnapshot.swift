import AppKit

/// A full capture of a pasteboard's contents: every item, every type. Used to
/// restore the user's clipboard exactly after we temporarily overwrite it for
/// a paste, so images, files, and rich text survive round-trip, not just
/// plain strings.
struct PasteboardSnapshot: Equatable {
    /// One entry per pasteboard item, each mapping type to its data.
    let items: [[NSPasteboard.PasteboardType: Data]]

    /// nspasteboard.org markers that password managers (1Password, Bitwarden,
    /// etc.) put on secrets. They auto-clear the clipboard later only if its
    /// changeCount hasn't moved; our restore moves it, so restoring a secret
    /// would leave it on the clipboard indefinitely.
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    /// Captures every item and type. A concealed or transient clipboard is
    /// captured as empty, so the restore clears our text instead of putting
    /// the secret back.
    static func capture(from pb: NSPasteboard) -> PasteboardSnapshot {
        let pbItems = pb.pasteboardItems ?? []
        if pbItems.contains(where: { !sensitiveTypes.isDisjoint(with: $0.types) }) {
            return PasteboardSnapshot(items: [])
        }
        let items: [[NSPasteboard.PasteboardType: Data]] = pbItems.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
        return PasteboardSnapshot(items: items)
    }

    /// Writes this snapshot back to `pb`, replacing whatever is there now.
    /// An empty snapshot (nothing was on the pasteboard at capture time)
    /// restores to an empty pasteboard rather than leaving our own contents
    /// in place.
    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let pasteboardItems: [NSPasteboardItem] = items.map { typeMap in
            let item = NSPasteboardItem()
            for (type, data) in typeMap {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(pasteboardItems)
    }

    var isEmpty: Bool { items.isEmpty }
}
