//
//  SpeedLimitSignView.swift
//  Demonic Speed Display
//
//  Tempolimit als Verkehrszeichen (Zeichen 274 / 282 nachempfunden).
//

import CoreGraphics
import Foundation
import SwiftUI

struct SpeedLimitSignView: View {
    let status: SpeedLimitStatus
    let diameter: CGFloat

    var body: some View {
        Group {
            switch status {
            case .known(let limit):
                switch limit.value {
                case .kmh(let value): limitSign(number: value, unit: nil)
                case .mph(let value): limitSign(number: value, unit: "mph")
                case .unlimited: unlimitedSign
                }
            case .unknown:
                unknownSign
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func limitSign(number: Int, unit: String?) -> some View {
        let digits = String(number).count
        let fontSize = diameter * (digits >= 3 ? 0.36 : 0.46)
        return ZStack {
            Circle().fill(Theme.signWhite)
            Circle().strokeBorder(Theme.signRed, lineWidth: diameter * 0.11)
            VStack(spacing: 0) {
                Text(verbatim: "\(number)")
                    .font(.system(size: fontSize, weight: .bold, design: .default))
                    .monospacedDigit()
                    .tracking(-diameter * 0.01)
                if let unit {
                    Text(verbatim: unit)
                        .font(.system(size: diameter * 0.1, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.signBlack)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(diameter * 0.16)
        }
        .shadow(color: Theme.ember.opacity(0.55), radius: diameter * 0.08)
    }

    private var unlimitedSign: some View {
        ZStack {
            Circle().fill(Theme.signWhite)
            HStack(spacing: diameter * 0.045) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Theme.signBlack)
                        .frame(width: diameter * 0.03)
                }
            }
            .frame(width: diameter * 0.4, height: diameter * 1.2)
            .rotationEffect(.degrees(45))
            .clipShape(Circle().inset(by: diameter * 0.12))
            Circle().strokeBorder(Theme.signBlack.opacity(0.25), lineWidth: diameter * 0.02)
        }
        .clipShape(Circle())
        .shadow(color: Theme.ember.opacity(0.4), radius: diameter * 0.06)
    }

    private var unknownSign: some View {
        ZStack {
            Circle().fill(Theme.surface)
            Circle().strokeBorder(Theme.textSecondary.opacity(0.7),
                                  style: StrokeStyle(lineWidth: diameter * 0.05,
                                                     dash: [diameter * 0.09, diameter * 0.06]))
            Text(verbatim: "?")
                .font(.system(size: diameter * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var accessibilityText: String {
        switch status {
        case .known(let limit):
            switch limit.value {
            case .kmh(let v): return "Tempolimit \(v) Kilometer pro Stunde"
            case .mph(let v): return "Tempolimit \(v) Meilen pro Stunde"
            case .unlimited: return "Keine Geschwindigkeitsbeschränkung"
            }
        case .unknown(let reason):
            return "Tempolimit unbekannt. \(reason.explanation)"
        }
    }
}

/// Zeichen samt Beschriftung darunter.
struct SpeedLimitPanel: View {
    let status: SpeedLimitStatus
    let diameter: CGFloat
    let isDemo: Bool

    var body: some View {
        VStack(spacing: 10) {
            SpeedLimitSignView(status: status, diameter: diameter)
            caption
                .multilineTextAlignment(.center)
                .frame(maxWidth: max(diameter * 1.6, 180))
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch status {
        case .known(let limit):
            VStack(spacing: 3) {
                Text(title(for: limit.value))
                    .font(Theme.label(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let road = limit.roadName, !road.isEmpty {
                    Text(verbatim: road)
                        .font(Theme.label(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if limit.isImplicit {
                    Text("aus gesetzlicher Zonenangabe")
                        .font(Theme.label(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                if isDemo { demoTag }
            }
        case .unknown(let reason):
            VStack(spacing: 3) {
                Text("Tempolimit unbekannt")
                    .font(Theme.label(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(reason.explanation)
                    .font(Theme.label(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                if isDemo { demoTag }
            }
        }
    }

    private var demoTag: some View {
        Text("DEMO-LIMIT")
            .font(Theme.label(11, weight: .heavy))
            .tracking(1.5)
            .foregroundStyle(Theme.violet)
    }

    private func title(for value: SpeedLimitValue) -> String {
        switch value {
        case .kmh: return "Erlaubte Höchstgeschwindigkeit"
        case .mph: return "Erlaubte Höchstgeschwindigkeit (mph)"
        case .unlimited: return "Keine Beschränkung erfasst"
        }
    }
}
