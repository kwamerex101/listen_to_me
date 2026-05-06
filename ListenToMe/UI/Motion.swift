//
//  Motion.swift
//  ListenToMe
//
//  Single-source spring vocabulary for all UI motion. Tuning the feel of
//  the app happens here — pill morphs, tab transitions, micro-animations.
//

import SwiftUI

enum Motion {
    // --- Existing pill vocabulary (preserved verbatim from PillView) ---

    /// Size morphs (width/height) between phases. Snappy but never overshoots.
    static let phaseSize  = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// Content swap (id transition). Slightly looser to let the new content
    /// land with a touch of life without bouncing.
    static let phaseSwap  = Animation.spring(response: 0.40, dampingFraction: 0.72)
    /// Press-pop scale beat when recording starts.
    static let pressUp    = Animation.spring(response: 0.18, dampingFraction: 0.55)
    static let pressDown  = Animation.spring(response: 0.32, dampingFraction: 0.55)
    /// Success spring for the checkmark scale-in.
    static let successPop = Animation.spring(response: 0.32, dampingFraction: 0.55)
    /// Halo expand-and-fade after a successful paste.
    static let halo       = Animation.easeOut(duration: 0.45)
    /// Error shake — mirrors macOS's native NSWindow.shake feel.
    static let shake      = Animation.easeInOut(duration: 0.45)
    /// Idle breath (autoreversing) — long enough to fade into background.
    static let idleBreath = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    /// Stop-button reactive scale to live audio level.
    static let stopReact  = Animation.spring(response: 0.18, dampingFraction: 0.7)

    // --- Phase 5 additions ---

    /// MainView tab content cross-fade (Q3 locked: 200ms easeInOut, content only).
    static let tabFade        = Animation.easeInOut(duration: 0.20)

    /// Pill waveform dim after 5s silence (POLISH-04a / Wispr W4).
    static let silenceDim     = Animation.easeOut(duration: 0.4)

    /// Pill waveform wake on speech return (POLISH-04a inverse).
    static let silenceWake    = Animation.spring(response: 0.18, dampingFraction: 0.7)

    /// Gold ring on dictionary candidate auto-promotion (POLISH-04c — moment of delight).
    static let promotionFlash = Animation.easeOut(duration: 0.6)
}
