//
//  HoverableRow.swift
//  ListenToMe
//
//  Subtle background-fill hover for any row-shaped surface.
//  150ms easeInOut, no scale (avoids reflow flicker at row boundaries).
//

import SwiftUI

struct HoverableRow: ViewModifier {
    var hoveredFill: Color = Color.primary.opacity(0.05)
    var restingFill: Color = .clear
    var cornerRadius: CGFloat = 8
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovered ? hoveredFill : restingFill)
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: hovered)
    }
}

extension View {
    func hoverableRow(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverableRow(cornerRadius: cornerRadius))
    }
}
