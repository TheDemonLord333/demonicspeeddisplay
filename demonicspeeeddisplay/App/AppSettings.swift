//
//  AppSettings.swift
//  Demonic Speed Display
//

import Foundation
import Observation

@Observable
final class AppSettings {
    private enum Key {
        static let warningEnabled = "overspeedWarningEnabled"
        static let tolerance = "overspeedTolerance"
        static let soundEnabled = "overspeedSoundEnabled"
        static let keepScreenOn = "keepScreenOn"
        static let endpoint = "overpassEndpoint"
        static let demoEnabled = "demoModeEnabled"
        static let demoAuto = "demoAutoCycle"
        static let demoSpeed = "demoSpeed"
        static let demoLimit = "demoLimit"
    }

    /// Im Simulator bleibt der Demo-Modus über Neustarts erhalten. Auf echten
    /// Geräten startet die App immer mit echten Messwerten.
    static var persistsDemoMode: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    @ObservationIgnored private let defaults: UserDefaults

    var overspeedWarningEnabled: Bool { didSet { defaults.set(overspeedWarningEnabled, forKey: Key.warningEnabled) } }
    /// Toleranz in km/h, ab der ein Hinweis erscheint.
    var overspeedTolerance: Int { didSet { defaults.set(overspeedTolerance, forKey: Key.tolerance) } }
    var overspeedSoundEnabled: Bool { didSet { defaults.set(overspeedSoundEnabled, forKey: Key.soundEnabled) } }
    var keepScreenOn: Bool { didSet { defaults.set(keepScreenOn, forKey: Key.keepScreenOn) } }
    var overpassEndpoint: String { didSet { defaults.set(overpassEndpoint, forKey: Key.endpoint) } }

    var demoModeEnabled: Bool {
        didSet { if Self.persistsDemoMode { defaults.set(demoModeEnabled, forKey: Key.demoEnabled) } }
    }
    var demoAutoCycle: Bool { didSet { defaults.set(demoAutoCycle, forKey: Key.demoAuto) } }
    var demoSpeed: Double { didSet { defaults.set(demoSpeed, forKey: Key.demoSpeed) } }
    var demoLimit: DemoLimitOption { didSet { defaults.set(demoLimit.rawValue, forKey: Key.demoLimit) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.warningEnabled: true,
            Key.tolerance: 3,
            Key.soundEnabled: false,
            Key.keepScreenOn: true,
            Key.endpoint: OverpassClient.defaultEndpoint.absoluteString,
            // Im Simulator gibt es kein GPS – dort startet die App beim ersten Mal im Demo-Modus.
            Key.demoEnabled: Self.persistsDemoMode,
            Key.demoAuto: true,
            Key.demoSpeed: 57.0,
            Key.demoLimit: DemoLimitOption.kmh50.rawValue,
        ])
        overspeedWarningEnabled = defaults.bool(forKey: Key.warningEnabled)
        overspeedTolerance = min(15, max(0, defaults.integer(forKey: Key.tolerance)))
        overspeedSoundEnabled = defaults.bool(forKey: Key.soundEnabled)
        keepScreenOn = defaults.bool(forKey: Key.keepScreenOn)
        overpassEndpoint = defaults.string(forKey: Key.endpoint) ?? OverpassClient.defaultEndpoint.absoluteString
        demoModeEnabled = Self.persistsDemoMode ? defaults.bool(forKey: Key.demoEnabled) : false
        demoAutoCycle = defaults.bool(forKey: Key.demoAuto)
        demoSpeed = defaults.double(forKey: Key.demoSpeed)
        demoLimit = DemoLimitOption(rawValue: defaults.integer(forKey: Key.demoLimit)) ?? .kmh50
    }

    /// Gültige HTTPS-Adresse des Overpass-Servers oder `nil`.
    static func validatedEndpoint(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var endpointURL: URL {
        Self.validatedEndpoint(overpassEndpoint) ?? OverpassClient.defaultEndpoint
    }
}
