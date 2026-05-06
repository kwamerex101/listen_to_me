import SwiftUI

enum WfSection: String, CaseIterable, Identifiable {
    // Active sections shown in the sidebar.
    case home, dictionary, snippets, style, settings

    // Hidden / experimental sections — commented out of the sidebar list
    // because they're off-mission for a focused "speak once, ship clean
    // text" dictation tool. View files and stores are kept on disk so
    // they can be re-enabled by uncommenting these cases and adding them
    // back to SidebarView's main-nav ForEach + MainView's switch.
    // case transforms
    // case scratchpad
    // case pages
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .settings: return "Settings"
        // case .transforms: return "Transforms"
        // case .scratchpad: return "Scratchpad"
        // case .pages: return "Pages"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .dictionary: return "doc.text"
        case .snippets: return "scissors"
        case .style: return "textformat"
        case .settings: return "gearshape"
        // case .transforms: return "wand.and.stars"
        // case .scratchpad: return "note.text"
        // case .pages: return "doc.plaintext"
        }
    }
}

struct MainView: View {
    @State private var selection: WfSection = .home

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 230)
                .background(Color(.controlBackgroundColor))

            Divider()

            Group {
                switch selection {
                case .home: HomeView()
                case .dictionary: DictionaryView()
                case .snippets: SnippetsView()
                case .style: StyleView()
                case .settings: SettingsView()
                // case .transforms: TransformsView()
                // case .scratchpad: ScratchpadView()
                // case .pages: PagesView()
                }
            }
            .id(selection)                                  // forces identity transition
            .transition(.opacity)                           // cross-fade
            .animation(Motion.tabFade, value: selection)    // 200ms easeInOut (content only — sidebar stays static)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
        }
        // The host fills available space; the AppKit window enforces the
        // hard minimum via contentMinSize (see MainWindowController).
        // SwiftUI minWidth/minHeight here matches the window minimum so the
        // layout never reports a smaller ideal back up to NSHostingController.
        .frame(minWidth: 880, maxWidth: .infinity, minHeight: 580, maxHeight: .infinity)
    }
}

struct PlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 60)              // clear the transparent title bar
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
    }
}
