//
//  DriveModel.swift
//  Demonic Speed Display
//
//  Verbindet Standortmessung, Tempolimit-Datenquelle, Demo-Modus und
//  Überschreitungshinweis. Die Oberfläche liest nur diesen Zustand.
//

import Foundation
import Observation
import UIKit

@Observable
final class DriveModel {
    enum DataOrigin: Equatable {
        /// Echte Messung vom GPS-Empfänger.
        case live
        /// Position aus einer Software-Simulation (z. B. Xcode) – echte Pipeline, aber keine echte Fahrt.
        case simulatedLocation
        /// Künstliche Demo-Werte.
        case demo
    }

    enum GPSQuality: Equatable {
        case none
        case poor
        case fair
        case good
    }

    let settings: AppSettings
    let location: LocationService
    let network: NetworkMonitor

    private(set) var reading: SpeedReading = .waiting
    private(set) var limitStatus: SpeedLimitStatus = .unknown(.noPosition)
    private(set) var isOverspeeding = false
    private(set) var origin: DataOrigin = .live
    private(set) var gpsQuality: GPSQuality = .none
    private(set) var sourceName: String
    private(set) var attribution: String

    /// Ganzzahlige Anzeige in km/h; `nil`, wenn kein gültiger Wert vorliegt.
    var displayedSpeed: Int? {
        if case .valid(let kmh) = reading { return Int(kmh.rounded()) }
        return nil
    }

    var isDemo: Bool { origin == .demo }

    @ObservationIgnored private var provider: any SpeedLimitProvider
    @ObservationIgnored private let validator = SpeedValidator()
    @ObservationIgnored private let announcer = OverspeedAnnouncer()
    @ObservationIgnored private var lastFix: LocationFix?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var demoStart = Date()
    @ObservationIgnored private var isActive = false

    init(settings: AppSettings,
         location: LocationService = LocationService(),
         network: NetworkMonitor = NetworkMonitor()) {
        self.settings = settings
        self.location = location
        self.network = network
        let provider = Self.makeProvider(settings: settings)
        self.provider = provider
        self.sourceName = provider.sourceName
        self.attribution = provider.attribution

        location.onFix = { [weak self] fix in self?.handle(fix) }
        provider.onDataChanged = { [weak self] in self?.recompute() }
    }

    private static func makeProvider(settings: AppSettings) -> any SpeedLimitProvider {
        OSMSpeedLimitProvider(source: OverpassClient(endpoint: settings.endpointURL))
    }

    // MARK: - Lebenszyklus

    func start() {
        guard !isActive else { return }
        isActive = true
        network.start()
        location.start()
        demoStart = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.recompute()
            }
        }
        applyIdleTimer()
        recompute()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        location.stop()
        tickTask?.cancel()
        tickTask = nil
        applyIdleTimer()
    }

    func requestLocationPermission() {
        location.requestPermission()
    }

    // MARK: - Einstellungen

    func endpointChanged() {
        provider.reset()
        provider.onDataChanged = nil
        let newProvider = Self.makeProvider(settings: settings)
        newProvider.onDataChanged = { [weak self] in self?.recompute() }
        provider = newProvider
        sourceName = newProvider.sourceName
        attribution = newProvider.attribution
        recompute()
    }

    func demoModeChanged() {
        demoStart = Date()
        isOverspeeding = false
        recompute()
    }

    func applyIdleTimer() {
        // Während der Fahrt soll das Display nicht abschalten.
        UIApplication.shared.isIdleTimerDisabled = isActive && settings.keepScreenOn
    }

    // MARK: - Auswertung

    private func handle(_ fix: LocationFix) {
        // Ältere, verspätet zugestellte Werte dürfen einen neueren nicht ersetzen.
        if let lastFix, fix.timestamp < lastFix.timestamp { return }
        lastFix = fix
        recompute()
    }

    func recompute(now: Date = Date()) {
        if settings.demoModeEnabled {
            let sample = DemoDrive.sample(elapsed: now.timeIntervalSince(demoStart),
                                          auto: settings.demoAutoCycle,
                                          manualSpeed: settings.demoSpeed,
                                          manualLimit: settings.demoLimit)
            origin = .demo
            reading = .valid(kmh: sample.speedKmh)
            limitStatus = sample.limit
            gpsQuality = .none
        } else {
            origin = (lastFix?.isSimulated ?? false) ? .simulatedLocation : .live
            reading = validator.evaluate(lastFix, now: now)
            gpsQuality = Self.quality(of: lastFix, now: now, maxAge: validator.maxAge)
            limitStatus = resolveLimit(now: now)
        }
        updateOverspeed()
    }

    private func resolveLimit(now: Date) -> SpeedLimitStatus {
        guard location.authorization == .authorized else { return .unknown(.noPosition) }
        guard let fix = lastFix else { return .unknown(.noPosition) }
        let age = now.timeIntervalSince(fix.timestamp)
        guard age <= validator.maxAge, age >= -1 else { return .unknown(.gpsInsufficient) }
        return provider.resolve(fix: fix, context: SpeedLimitContext(now: now, isOnline: network.isOnline))
    }

    private func updateOverspeed() {
        guard settings.overspeedWarningEnabled,
              let speed = displayedSpeed,
              let limit = limitStatus.limit?.value.kmhValue else {
            isOverspeeding = false
            return
        }
        let threshold = limit.rounded() + Double(settings.overspeedTolerance)
        let wasOverspeeding = isOverspeeding
        // Kleine Hysterese, damit der Hinweis an der Grenze nicht flackert.
        isOverspeeding = wasOverspeeding ? Double(speed) > threshold - 2 : Double(speed) > threshold
        if isOverspeeding && !wasOverspeeding && settings.overspeedSoundEnabled {
            announcer.announce()
        }
    }

    private static func quality(of fix: LocationFix?, now: Date, maxAge: TimeInterval) -> GPSQuality {
        guard let fix, now.timeIntervalSince(fix.timestamp) <= maxAge, fix.horizontalAccuracy >= 0 else {
            return .none
        }
        switch fix.horizontalAccuracy {
        case ...10: return .good
        case ...30: return .fair
        default: return .poor
        }
    }
}
