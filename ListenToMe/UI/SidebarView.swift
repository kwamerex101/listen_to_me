import SwiftUI

struct SidebarView: View {
    @Binding var selection: WfSection
    /// When true, the sidebar collapses to icons-only. Driven from MainView
    /// based on the window width crossing DT.compactBreakpoint.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo / brand row
            logoRow
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.top, 60)
                .padding(.bottom, DT.space4)

            Divider()
                .padding(.bottom, DT.space3)

            // Main nav
            VStack(spacing: 2) {
                ForEach([WfSection.home, .dictionary, .snippets, .style], id: \.self) { section in
                    NavRow(section: section, selected: selection == section, compact: compact) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, compact ? 8 : 10)

            Spacer()

            Divider()
                .padding(.top, DT.space2)

            // Bottom nav
            VStack(spacing: 2) {
                NavRow(section: .settings, selected: selection == .settings, compact: compact) {
                    selection = .settings
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.bottom, DT.space4)
            .padding(.top, DT.space2)
        }
        // Clip so collapsing transitions don't bleed across the divider.
        .clipped()
    }

    @ViewBuilder
    private var logoRow: some View {
        if compact {
            HStack {
                Spacer()
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DT.accent)
                Spacer()
            }
            .help("ListenToMe")
        } else {
            HStack(spacing: DT.space3) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.accent)
                Text("ListenToMe")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
        }
    }
}

private struct NavRow: View {
    let section: WfSection
    let selected: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .padding(.horizontal, compact ? 0 : 12)
                .padding(.vertical, compact ? 10 : 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.primary.opacity(0.09) : Color.clear)
                )
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .hoverableRow()
        }
        .buttonStyle(.pressable)
        .help(compact ? section.label : "")
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            Image(systemName: section.sfSymbol)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .frame(width: 32, height: 22)
                .foregroundStyle(selected ? .primary : .secondary)
        } else {
            HStack(spacing: 10) {
                Image(systemName: section.sfSymbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? .primary : .secondary)
                Text(section.label)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer(minLength: 0)
            }
        }
    }
}
