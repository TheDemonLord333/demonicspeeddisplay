//
//  Theme.swift
//  Demonic Speed Display
//
//  Dämonisches, aber ruhiges Farbschema: fast schwarz, dunkelrot, violett,
//  dezente Glut. Keine Animationen.
//

import CoreGraphics
import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.02, blue: 0.035)
    static let surface = Color(red: 0.09, green: 0.05, blue: 0.09)
    static let surfaceStroke = Color(red: 0.28, green: 0.12, blue: 0.26)

    static let ember = Color(red: 0.62, green: 0.05, blue: 0.09)
    static let emberBright = Color(red: 1.0, green: 0.24, blue: 0.2)
    static let violet = Color(red: 0.55, green: 0.3, blue: 0.9)
    static let violetDeep = Color(red: 0.26, green: 0.08, blue: 0.42)

    static let textPrimary = Color(red: 0.97, green: 0.95, blue: 0.96)
    static let textSecondary = Color(red: 0.68, green: 0.62, blue: 0.68)
    static let caution = Color(red: 1.0, green: 0.66, blue: 0.25)

    /// Verkehrszeichen-Farben (bewusst normnah, nicht thematisiert).
    static let signWhite = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let signRed = Color(red: 0.8, green: 0.07, blue: 0.1)
    static let signBlack = Color(red: 0.05, green: 0.05, blue: 0.05)

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Hintergrund mit dezenter, statischer Glut an den Rändern.
struct DemonicBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.violetDeep.opacity(0.45), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.ember.opacity(0.35), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// Kleine Kapsel für Statusangaben.
struct StatusChip: View {
    let systemImage: String
    let text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(Theme.label(12))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.surface.opacity(0.85)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
