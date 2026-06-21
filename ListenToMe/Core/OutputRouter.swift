import Foundation

/// Delivers finished dictation text to the non-paste destinations. The
/// `.activeApp` path stays in AppDelegate (it owns the paste-token/replace
/// lifecycle); this type owns only the Apple Notes path.
enum OutputRouter {

    /// Write `text` into Apple Notes per the user's note-mode/folder/title
    /// preferences. Runs the blocking NotesWriter executor off the main actor.
    static func deliverToNotes(text: String) async -> Result<Void, NotesWriter.NotesError> {
        let mode = Preferences.shared.noteMode
        let folder = Preferences.shared.noteFolder
        let title = Preferences.shared.noteTitle
        return await Task.detached(priority: .userInitiated) {
            NotesWriter.write(text: text, mode: mode, folder: folder, defaultTitle: title)
        }.value
    }
}
