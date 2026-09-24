//
//  SettingsView.swift
//  Demonic Speed Display
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DriveModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var usesCustomEndpoint = false
    @State private var customEndpoint = ""
    @State private var customEndpointError: String?

    private static let customTag = "custom"

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Hinweis bei Überschreitung", isOn: $settings.overspeedWarningEnabled)
                    Stepper(value: $settings.overspeedTolerance, in: 0...15) {
                        Text("Toleranz: +\(settings.overspeedTolerance) km/h")
                    }
                    .disabled(!settings.overspeedWarningEnabled)
                    Toggle("Kurzer Sprachhinweis", isOn: $settings.overspeedSoundEnabled)
                        .disabled(!settings.overspeedWarningEnabled)
                } header: {
                    Text("Überschreitung")
                } footer: {
                    Text("Die Zahl wird rot und bekommt einen ruhigen Rahmen – ohne Blinken. Der Sprachhinweis kommt höchstens alle 30 Sekunden. Nur bei erkanntem Limit.")
                }

                Section("Anzeige") {
                    Toggle("Bildschirm eingeschaltet lassen", isOn: $settings.keepScreenOn)
                }

                dataSourceSection

                Section {
                    Toggle("Demo-Modus", isOn: $settings.demoModeEnabled)
                    if settings.demoModeEnabled {
                        Toggle("Automatischer Ablauf", isOn: $settings.demoAutoCycle)
                        if !settings.demoAutoCycle {
                            VStack(alignment: .leading) {
                                Text("Testgeschwindigkeit: \(Int(settings.demoSpeed)) km/h")
                                Slider(value: $settings.demoSpeed, in: 0...220, step: 1)
                            }
                            Picker("Testlimit", selection: $settings.demoLimit) {
                                ForEach(DemoLimitOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Demo (Simulator)")
                } footer: {
                    Text("Zeigt künstliche Testwerte, überall deutlich als DEMO gekennzeichnet. Auf dem iPhone startet die App immer mit echten Messwerten.")
                }

                Section("Wichtig") {
                    Text("Verkehrszeichen vor Ort sind immer maßgeblich. Die Kartendaten können fehlen, veraltet sein oder variable, temporäre (Baustellen) und bedingte Limits (Uhrzeit, Nässe, Lkw) nicht abbilden. In solchen Fällen zeigt die App „Tempolimit unbekannt“ statt eines geschätzten Werts.")
                        .font(.footnote)
                    Text("Bitte die App nicht während der Fahrt bedienen.")
                        .font(.footnote.weight(.semibold))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear(perform: loadEndpointState)
        }
        .tint(Theme.emberBright)
        .preferredColorScheme(.dark)
    }

    private var dataSourceSection: some View {
        Section {
            LabeledContent("Anbieter", value: model.sourceName)
            Picker("Server", selection: endpointSelection) {
                ForEach(OverpassClient.knownEndpoints) { endpoint in
                    Text(endpoint.name).tag(endpoint.url)
                }
                Text("Eigener Server").tag(Self.customTag)
            }
            if usesCustomEndpoint {
                TextField("https://…/api/interpreter", text: $customEndpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Server übernehmen", action: applyCustomEndpoint)
                if let customEndpointError {
                    Text(customEndpointError)
                        .font(.footnote)
                        .foregroundStyle(Theme.caution)
                }
            }
        } header: {
            Text("Tempolimit-Datenquelle")
        } footer: {
            Text("Zur Abfrage wird deine Position an den gewählten Overpass-Server gesendet. Straßen werden je nach Tempo im Umkreis von 0,8–2 km vorausgeladen, neu geladen wird erst kurz vor Verlassen des Bereichs. \(model.attribution).")
        }
    }

    private var endpointSelection: Binding<String> {
        Binding(
            get: {
                usesCustomEndpoint ? Self.customTag : settings.overpassEndpoint
            },
            set: { newValue in
                if newValue == Self.customTag {
                    usesCustomEndpoint = true
                    customEndpoint = isKnown(settings.overpassEndpoint) ? "" : settings.overpassEndpoint
                } else {
                    usesCustomEndpoint = false
                    customEndpointError = nil
                    settings.overpassEndpoint = newValue
                }
            }
        )
    }

    private func isKnown(_ url: String) -> Bool {
        OverpassClient.knownEndpoints.contains { $0.url == url }
    }

    private func loadEndpointState() {
        usesCustomEndpoint = !isKnown(settings.overpassEndpoint)
        customEndpoint = usesCustomEndpoint ? settings.overpassEndpoint : ""
    }

    private func applyCustomEndpoint() {
        guard let url = AppSettings.validatedEndpoint(customEndpoint) else {
            customEndpointError = "Bitte eine gültige https-Adresse eingeben."
            return
        }
        customEndpointError = nil
        settings.overpassEndpoint = url.absoluteString
    }
}
