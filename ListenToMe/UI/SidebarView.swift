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
                Text("Basic")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)      // clear the transparent title bar
            .padding(.bottom, 28)

            // Main nav
            VStack(spacing: 4) {
                ForEach([WfSection.home, .dictionary, .snippets, .style, .transforms, .scratchpad], id: \.self) { section in
                    NavRow(section: section, selected: selection == section) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Bottom nav
            VStack(spacing: 4) {
                NavRow(section: .settings, selected: selection == .settings) {
                    selection = .settings
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
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
                Text(section.label)
                    .font(.system(size: 14))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.09) : Color.clear)
            )
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
