//
//  SpeedReadoutView.swift
//  Demonic Speed Display
//
//  Die aktuelle Geschwindigkeit – das größte Element. Ungültige oder alte
//  Werte werden nie als Zahl gezeigt, sondern als „– –“ mit Begründung.
//

import CoreGraphics
import Foundation
import SwiftUI

struct SpeedReadoutView: View {
    let reading: SpeedReading
    let origin: DriveModel.DataOrigin
    let isOverspeeding: Bool

    var body: some View {
        GeometryReader { geo in
            let numberSize = min(geo.size.width / 1.95, geo.size.height * 0.68)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                number(size: numberSize)
                Text("km/h")
                    .font(Theme.label(max(16, numberSize * 0.16), weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textSecondary)
                statusLine
                    .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(isOverspeeding ? Theme.emberBright : .clear, lineWidth: 3)
        )
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func number(size: CGFloat) -> some View {
        switch reading {
        case .valid(let kmh):
            Text(verbatim: "\(Int(kmh.rounded()))")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isOverspeeding ? Theme.emberBright : Theme.textPrimary)
                .shadow(color: (isOverspeeding ? Theme.emberBright : Theme.ember).opacity(0.55),
                        radius: size * 0.06)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.identity)
                .accessibilityLabel("\(Int(kmh.rounded())) Kilometer pro Stunde")
        default:
            Text(verbatim: "– –")
                .font(.system(size: size * 0.8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityLabel("Keine gültige Geschwindigkeit")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch reading {
        case .valid:
            switch origin {
            case .demo:
                tag("DEMO-WERT · KEINE ECHTE MESSUNG", color: Theme.violet)
            case .simulatedLocation:
                tag("SIMULIERTE POSITION", color: Theme.violet)
            case .live:
                if isOverspeeding {
                    tag("LIMIT ÜBERSCHRITTEN", color: Theme.emberBright)
                } else {
                    tag("GPS", color: Theme.textSecondary.opacity(0.7))
                }
            }
        case .waiting:
            tag("SUCHE GPS-SIGNAL …", color: Theme.caution)
        case .stale:
            tag("GPS-SIGNAL VERLOREN", color: Theme.caution)
        case .inaccurate:
            tag("GPS-EMPFANG ZU SCHWACH", color: Theme.caution)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(Theme.label(13, weight: .heavy))
            .tracking(1.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
