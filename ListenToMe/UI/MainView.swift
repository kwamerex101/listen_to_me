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

    /// Filled / "selected" variant of the symbol. For symbols without a
    /// dedicated `.fill` glyph (scissors, textformat) we keep the same
    /// outline but apply a coloured tint via `selectedTint` below — that
    /// alone reads clearly as "selected".
    var selectedSymbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .dictionary: return "doc.text.fill"
        case .snippets: return "scissors"            // no .fill variant
        case .style: return "textformat"             // no .fill variant
        case .settings: return "gearshape.fill"
        }
    }

    /// Per-section accent color used in the sidebar when this section is
    /// the active selection. Matches the page-header badge tint used on
    /// each page so visual identity is consistent across the app.
    var selectedTint: Color {
        switch self {
        case .home: return .blue
        case .dictionary: return .teal
        case .snippets: return .pink
        case .style: return .indigo
        case .settings: return .gray
        }
    }
}

struct MainView: View {
    @State private var selection: WfSection = .home

    var body: some View {
        // GeometryReader at the root drives the responsive size class for the
        // entire window. Children read it via the `windowWidth` environment.
        GeometryReader { geo in
            let isCompact = geo.size.width < DT.compactBreakpoint

            HStack(spacing: 0) {
                SidebarView(selection: $selection, compact: isCompact)
                    .frame(width: isCompact ? DT.sidebarCompactWidth : DT.sidebarRegularWidth)
                    .background(Color(.controlBackgroundColor))
                    .animation(.easeInOut(duration: 0.18), value: isCompact)

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
                .id(selection)
                .transition(.opacity)
                .animation(Motion.tabFade, value: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
            }
            // Push the window's measured width down so any descendant can
            // ask `@Environment(\.windowWidth)` and respond with explicit
            // size-class behaviour instead of re-measuring.
            .environment(\.windowWidth, geo.size.width)
        }
        // SwiftUI floor matches the AppKit window contentMinSize. The window
        // controller hard-clamps user resizes against this.
        .frame(
            minWidth: DT.windowMinWidth,
            maxWidth: .infinity,
            minHeight: DT.windowMinHeight,
            maxHeight: .infinity
        )
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
