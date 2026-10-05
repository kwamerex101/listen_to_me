import SwiftUI

struct SidebarView: View {
    @Binding var selection: WfSection
    /// When true, the sidebar collapses to icons-only. Driven from MainView
    /// based on the window width crossing DT.compactBreakpoint.
    var compact: Bool = false

    @Namespace private var selectionNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo / brand row
            logoRow
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.top, DT.safeAreaTop)
                .padding(.bottom, DT.space4)

            Divider()
                .padding(.bottom, DT.space3)

            // Main nav
            VStack(spacing: 2) {
                ForEach([WfSection.home, .history, .dictionary, .snippets, .style], id: \.self) { section in
                    NavRow(section: section, selected: selection == section, compact: compact, namespace: selectionNS) {
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
                NavRow(section: .settings, selected: selection == .settings, compact: compact, namespace: selectionNS) {
                    selection = .settings
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.bottom, DT.space4)
            .padding(.top, DT.space2)
        }
        // Slides the selected-row highlight between rows.
        .animation(reduceMotion ? nil : Motion.selection, value: selection)
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
                    .font(DT.sectionTitle)
                Spacer()
            }
        }
    }
}

private struct NavRow: View {
    let section: WfSection
    let selected: Bool
    let compact: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .padding(.horizontal, compact ? 0 : 12)
                .padding(.vertical, compact ? 10 : 8)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .hoverableRow()
        }
        .buttonStyle(.pressable)
        // ⌘1…⌘6 follow `WfSection.allCases` order (sidebar order).
        .keyboardShortcut(shortcutKey, modifiers: .command)
        .help("\(section.label) (⌘\(shortcutNumber))")
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var shortcutNumber: Int {
        (WfSection.allCases.firstIndex(of: section) ?? 0) + 1
    }

    private var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character("\(shortcutNumber)"))
    }

    /// Symbol shown for this row's current state — the filled / coloured
    /// variant when selected, the neutral outline otherwise.
    private var symbolName: String {
        selected ? section.selectedSymbol : section.sfSymbol
    }

    /// Foreground color for the icon. Selected → the section's unique tint;
    /// unselected → secondary neutral.
    private var iconColor: Color {
        selected ? section.selectedTint : .secondary
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .frame(width: 32, height: 22)
                .foregroundStyle(iconColor)
                .contentTransition(.symbolEffect(.replace))
        } else {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect(.replace))
                Text(section.label)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer(minLength: 0)
            }
        }
    }
}
