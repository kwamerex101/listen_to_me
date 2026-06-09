import SwiftUI

/// Resolve a `bundleId` to a friendly display name + a stable color.
/// Color is a hash of the bundleId so repeat apps get the same tint
/// across launches without persisting anything extra. Shared by the
/// Home "Where you dictate" card and the History app filter.
enum AppDisplay {
    static func nameAndTint(for bundleId: String?) -> (String, Color) {
        guard let bundleId else { return ("Other", .gray) }
        let name = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId)
            .first?.localizedName
            ?? bundleId.components(separatedBy: ".").last
            ?? bundleId
        let palette: [Color] = [.blue, .teal, .indigo, .pink, .orange, .purple, .green, .mint, .cyan, .red]
        let hash = abs(bundleId.hashValue)
        return (name, palette[hash % palette.count])
    }
}

/// One transcript row — timestamp, text, and hover actions (transform,
/// copy, delete). Used by the Home "Today" section and the History page.
struct RecordRow: View {
    let record: TranscriptRecord
    /// Show the target-app tint dot + name under the timestamp. History
    /// lists records across many apps, so identity matters there; Home's
    /// Today section keeps the row compact.
    var showApp: Bool = false

    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var transformsStore = TransformsStore.shared
    @State private var hovered = false
    @State private var copied = false
    @State private var transforming = false
    @State private var transformedFlash = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: DT.space5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.fmt.string(from: record.timestamp))
                    .font(DT.monoCaption)
                    .foregroundStyle(.secondary)
                if showApp {
                    let (name, tint) = AppDisplay.nameAndTint(for: record.bundleId)
                    HStack(spacing: 4) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 78, alignment: .leading)
            .padding(.top, 2)

            if record.dismissed {
                Text("This transcription was dismissed.")
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(record.finalText)
                    .font(DT.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !record.dismissed {
                HStack(spacing: 4) {
                    transformMenu
                    actionButton(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        help: copied ? "Copied" : "Copy transcript",
                        action: copyText
                    )
                    actionButton(
                        icon: "trash",
                        help: "Delete transcript",
                        action: { history.remove(id: record.id) }
                    )
                }
                .opacity(hovered ? 1 : 0.32)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space4)
        .background(hovered ? DT.accent.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DT.accent)
                .frame(width: hovered ? 3 : 0)
                .animation(.easeInOut(duration: 0.12), value: hovered)
        }
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    private func actionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.07 : 0))
                )
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.finalText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    /// Polish/Transform menu — built-ins from BuiltinTransform.all plus
    /// any user-defined entries from TransformsStore. Selecting an item
    /// runs the transform via Claude and writes the result to the
    /// pasteboard (we don't auto-paste — the user is reviewing history,
    /// not actively dictating into a focused field).
    private var transformMenu: some View {
        Menu {
            Section("Polish / Transform") {
                ForEach(BuiltinTransform.all) { t in
                    Button(t.label) {
                        runTransform(label: t.label, instruction: t.instruction)
                    }
                }
            }
            if !transformsStore.transforms.isEmpty {
                Section("Custom") {
                    ForEach(transformsStore.transforms) { t in
                        Button(t.name) {
                            runTransform(label: t.name, instruction: t.prompt)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: transforming ? "ellipsis.circle"
                                           : (transformedFlash ? "checkmark" : "wand.and.stars"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.07 : 0))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Polish / Transform")
        .disabled(transforming)
    }

    private func runTransform(label: String, instruction: String) {
        guard !record.finalText.isEmpty, !transforming else { return }
        transforming = true
        let input = record.finalText
        Task { @MainActor in
            do {
                let result = try await ClaudeClient.shared.transform(
                    text: input,
                    transformInstruction: instruction
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                transforming = false
                transformedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    transformedFlash = false
                }
                NSLog("[ListenToMe] transform '\(label)' → pasteboard (\(result.count) chars)")
            } catch {
                transforming = false
                NSLog("[ListenToMe] transform '\(label)' failed: \(error)")
            }
        }
    }
}
