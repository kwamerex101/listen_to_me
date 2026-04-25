import SwiftUI

enum WfSection: String, CaseIterable, Identifiable {
    case home, dictionary, snippets, style, transforms, scratchpad, pages, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .transforms: return "Transforms"
        case .scratchpad: return "Scratchpad"
        case .pages: return "Pages"
        case .settings: return "Settings"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .dictionary: return "doc.text"
        case .snippets: return "scissors"
        case .style: return "textformat"
        case .transforms: return "wand.and.stars"
        case .scratchpad: return "note.text"
        case .pages: return "doc.plaintext"
        case .settings: return "gearshape"
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
                case .transforms: TransformsView()
                case .scratchpad: ScratchpadView()
                case .pages: PagesView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
        }
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
