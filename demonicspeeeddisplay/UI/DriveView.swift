//
//  DriveView.swift
//  Demonic Speed Display
//
//  Hauptansicht. Hochformat: Geschwindigkeit oben, Zeichen darunter.
//  Querformat: Geschwindigkeit links, Zeichen rechts daneben.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct DriveView: View {
    @Environment(DriveModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        ZStack {
            DemonicBackground()
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                VStack(spacing: landscape ? 6 : 12) {
                    TopBar(showSettings: $showSettings)
                    if model.isDemo {
                        DemoBanner()
                    }
                    if !model.isDemo, let blocker = permissionBlocker {
                        PermissionCard(kind: blocker)
                            .frame(maxHeight: .infinity)
                    } else {
                        if !model.isDemo, !model.location.isPreciseLocation {
                            NoticeRow(systemImage: "location.slash",
                                      text: "Nur ungefährer Standort freigegeben – Geschwindigkeit nicht messbar. Bitte „Genauer Standort“ in den Einstellungen aktivieren.",
                                      tint: Theme.caution)
                        }
                        dashboard(size: geo.size, landscape: landscape)
                    }
                    DisclaimerFooter(attribution: model.attribution)
                }
                .padding(.horizontal, landscape ? 12 : 16)
                .padding(.vertical, 8)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
                .environment(settings)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.start()
            case .background: model.stop()
            default: break
            }
        }
        .onChange(of: settings.overpassEndpoint) { _, _ in model.endpointChanged() }
        .onChange(of: settings.demoModeEnabled) { _, _ in model.demoModeChanged() }
        .onChange(of: settings.keepScreenOn) { _, _ in model.applyIdleTimer() }
    }

    private var permissionBlocker: PermissionCard.Kind? {
        switch model.location.authorization {
        case .authorized: return nil
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        }
    }

    @ViewBuilder
    private func dashboard(size: CGSize, landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: 16) {
                SpeedReadoutView(reading: model.reading, origin: model.origin,
                                 isOverspeeding: model.isOverspeeding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SpeedLimitPanel(status: model.limitStatus,
                                diameter: min(size.height * 0.46, size.width * 0.24),
                                isDemo: model.isDemo)
                    .frame(width: max(size.width * 0.3, 190))
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                SpeedReadoutView(reading: model.reading, origin: model.origin,
                                 isOverspeeding: model.isOverspeeding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                SpeedLimitPanel(status: model.limitStatus,
                                diameter: min(size.width * 0.46, size.height * 0.24),
                                isDemo: model.isDemo)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Kopfzeile

private struct TopBar: View {
    @Environment(DriveModel.self) private var model
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("DEMONIC SPEED")
                .font(Theme.label(13, weight: .heavy))
                .tracking(3)
                .foregroundStyle(Theme.ember.opacity(0.95))
                .shadow(color: Theme.ember.opacity(0.8), radius: 6)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            if !model.isDemo {
                gpsChip
            }
            if !model.network.isOnline {
                StatusChip(systemImage: "wifi.slash", text: "Offline", tint: Theme.caution)
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Einstellungen")
        }
    }

    private var gpsChip: some View {
        switch model.gpsQuality {
        case .good:
            return StatusChip(systemImage: "location.fill", text: "GPS gut", tint: Theme.textSecondary)
        case .fair:
            return StatusChip(systemImage: "location.fill", text: "GPS mittel", tint: Theme.textSecondary)
        case .poor:
            return StatusChip(systemImage: "location", text: "GPS schwach", tint: Theme.caution)
        case .none:
            return StatusChip(systemImage: "location.slash", text: "Kein GPS", tint: Theme.caution)
        }
    }
}

// MARK: - Hinweise

private struct DemoBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
            Text("DEMO-MODUS – Testwerte, keine echte Messung")
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .font(Theme.label(13, weight: .heavy))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.violetDeep))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.violet, lineWidth: 1.5))
        .accessibilityLabel("Demo-Modus aktiv. Angezeigt werden Testwerte, keine echte Messung.")
    }
}

private struct NoticeRow: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.label(13, weight: .medium))
        .foregroundStyle(tint)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
    }
}

private struct DisclaimerFooter: View {
    let attribution: String

    var body: some View {
        VStack(spacing: 2) {
            Text("Verkehrszeichen vor Ort sind maßgeblich. Kartendaten können variable oder temporäre Limits übersehen.")
            Text(attribution)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
        .font(Theme.label(10.5, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }
}

private struct PermissionCard: View {
    enum Kind {
        case notDetermined
        case denied
        case restricted
    }

    let kind: Kind
    @Environment(DriveModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: kind == .notDetermined ? "location.circle" : "location.slash.circle")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.ember)
                .shadow(color: Theme.ember.opacity(0.7), radius: 12)
            Text(title)
                .font(Theme.label(22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.label(15, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            switch kind {
            case .notDetermined:
                primaryButton("Standort freigeben") { model.requestLocationPermission() }
            case .denied:
                primaryButton("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .restricted:
                EmptyView()
            }
            Button("Demo-Modus mit Testwerten starten") {
                settings.demoModeEnabled = true
            }
            .font(Theme.label(14, weight: .semibold))
            .foregroundStyle(Theme.violet)
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.surfaceStroke, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch kind {
        case .notDetermined: return "Standort benötigt"
        case .denied: return "Kein Standortzugriff"
        case .restricted: return "Standort eingeschränkt"
        }
    }

    private var message: String {
        switch kind {
        case .notDetermined:
            return "Um deine Geschwindigkeit zu messen und das Tempolimit der Straße zu finden, braucht die App deinen genauen Standort – nur solange sie geöffnet ist."
        case .denied:
            return "Der Standortzugriff ist verweigert oder die Ortungsdienste sind ausgeschaltet. Erlaube in den Einstellungen „Beim Verwenden der App“ und „Genauer Standort“."
        case .restricted:
            return "Der Standortzugriff ist auf diesem Gerät eingeschränkt (z. B. durch Bildschirmzeit oder ein Geräteprofil)."
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.label(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.ember))
                .overlay(Capsule().strokeBorder(Theme.emberBright.opacity(0.6), lineWidth: 1))
        }
    }
}
