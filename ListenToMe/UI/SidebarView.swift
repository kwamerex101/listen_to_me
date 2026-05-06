import SwiftUI

struct SidebarView: View {
    @Binding var selection: WfSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo row
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                Text("ListenToMe")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 12)

            // Main nav
            VStack(spacing: 2) {
                ForEach([WfSection.home, .dictionary, .snippets, .style, .transforms, .scratchpad, .pages], id: \.self) { section in
                    NavRow(section: section, selected: selection == section) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider()
                .padding(.top, 8)

            // Bottom nav
            VStack(spacing: 2) {
                NavRow(section: .settings, selected: selection == .settings) {
                    selection = .settings
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
    }
}

private struct NavRow: View {
    let section: WfSection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.sfSymbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? .primary : .secondary)
                Text(section.label)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.09) : Color.clear)
            )
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
