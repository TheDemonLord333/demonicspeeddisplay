//
//  OSMSpeedLimitProvider.swift
//  Demonic Speed Display
//
//  Tempolimit aus OpenStreetMap: lädt Straßen in einem Umkreis voraus
//  (in Fahrtrichtung versetzt), hält sie im Speicher und ordnet jede neue
//  Position lokal zu. Netzwerkanfragen entstehen nur, wenn der Bereich
//  verlassen wird oder die Daten zu alt sind – nicht bei jedem GPS-Ereignis.
//

import Foundation

@MainActor
final class OSMSpeedLimitProvider: SpeedLimitProvider {
    nonisolated struct Configuration: Sendable {
        /// Radius der Abfrage; wächst mit der Geschwindigkeit.
        var minRadius = 800.0
        var maxRadius = 2_000.0
        /// Sekunden Fahrt, die eine Abfrage etwa abdecken soll.
        var coverageSeconds = 80.0
        /// Anteil des Radius, um den der Mittelpunkt in Fahrtrichtung vorverlegt wird.
        /// Nach dem Laden bleiben so (1 − Anteil) × Radius Vorlauf.
        var lookAheadFraction = 0.4
        /// Neu laden, wenn weniger als so viele Sekunden Fahrt bis zum Rand bleiben.
        /// Muss deutlich kleiner sein als der Vorlauf nach dem Laden (siehe Test).
        var refetchLeadSeconds = 12.0
        var minRefetchLead = 200.0
        /// Nach dieser Zeit wird im Hintergrund neu geladen.
        var refreshAge: TimeInterval = 15 * 60
        /// Ältere Daten werden nicht mehr angezeigt.
        var maxDataAge: TimeInterval = 45 * 60
        /// Mindestabstand zwischen zwei Anfragen.
        var minRequestInterval: TimeInterval = 5
        var maxBackoff: TimeInterval = 120
    }

    private struct Coverage {
        let center: GeoCoordinate
        let radius: Double
        let fetchedAt: Date
        let ways: [RoadWay]
    }

    let sourceName = "OpenStreetMap (Overpass API)"
    let attribution = "Straßendaten © OpenStreetMap-Mitwirkende (ODbL)"
    var onDataChanged: (() -> Void)?

    private let source: any RoadGeometrySource
    private let matcher: RoadMatcher
    private let configuration: Configuration
    private let clock: () -> Date

    private var coverage: Coverage?
    private var memory: MatchMemory?
    private var fetchTask: Task<Void, Never>?
    private var nextAttempt = Date.distantPast
    private var failureCount = 0
    private var lastError: RoadDataError?

    /// Anzahl gestarteter Netzwerkanfragen (für Tests und Diagnose).
    private(set) var requestCount = 0

    init(source: any RoadGeometrySource,
         matcher: RoadMatcher = RoadMatcher(),
         configuration: Configuration = Configuration(),
         clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.matcher = matcher
        self.configuration = configuration
        self.clock = clock
    }

    var isFetching: Bool { fetchTask != nil }

    func resolve(fix: LocationFix, context: SpeedLimitContext) -> SpeedLimitStatus {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= matcher.maxUsableAccuracy else {
            return .unknown(.gpsInsufficient)
        }
        scheduleFetchIfNeeded(for: fix, context: context)

        guard let coverage, covers(coverage, fix.coordinate) else {
            memory = nil
            return .unknown(unavailableReason(isOnline: context.isOnline))
        }
        guard context.now.timeIntervalSince(coverage.fetchedAt) <= configuration.maxDataAge else {
            memory = nil
            return .unknown(.staleData)
        }
        let result = matcher.match(fix: fix, ways: coverage.ways, memory: memory)
        memory = result.memory
        return result.status
    }

    func reset() {
        fetchTask?.cancel()
        fetchTask = nil
        coverage = nil
        memory = nil
        lastError = nil
        failureCount = 0
        nextAttempt = .distantPast
    }

    // MARK: - Laden

    private func covers(_ coverage: Coverage, _ point: GeoCoordinate) -> Bool {
        GeoMath.distance(coverage.center, point) + matcher.maxMatchDistance <= coverage.radius
    }

    private func unavailableReason(isOnline: Bool) -> UnknownLimitReason {
        if fetchTask != nil { return .loading }
        if !isOnline { return .offline }
        switch lastError {
        case .none: return .loading
        case .offline: return .offline
        case .rateLimited: return .rateLimited
        default: return .networkError
        }
    }

    private func scheduleFetchIfNeeded(for fix: LocationFix, context: SpeedLimitContext) {
        let speed = max(0, fix.speed)
        if let coverage {
            let remaining = coverage.radius - GeoMath.distance(coverage.center, fix.coordinate)
            let lead = max(configuration.minRefetchLead, speed * configuration.refetchLeadSeconds)
            let tooOld = context.now.timeIntervalSince(coverage.fetchedAt) > configuration.refreshAge
            guard remaining < lead || tooOld else { return }
        }
        guard fetchTask == nil, context.isOnline, context.now >= nextAttempt else { return }

        let radius = min(configuration.maxRadius,
                         max(configuration.minRadius, speed * configuration.coverageSeconds))
        // Mittelpunkt in Fahrtrichtung vorverlegen, damit der Bereich länger reicht.
        var center = fix.coordinate
        if let course = fix.reliableCourse {
            center = GeoMath.offset(fix.coordinate, meters: radius * configuration.lookAheadFraction, bearing: course)
        }

        requestCount += 1
        let source = self.source
        fetchTask = Task { [weak self] in
            do {
                let ways = try await source.fetchRoads(center: center, radius: radius)
                self?.didFetch(ways, center: center, radius: radius)
            } catch is CancellationError {
                // reset() hat abgebrochen – nichts zu tun.
            } catch {
                self?.didFail(error)
            }
        }
    }

    private func didFetch(_ ways: [RoadWay], center: GeoCoordinate, radius: Double) {
        let now = clock()
        coverage = Coverage(center: center, radius: radius, fetchedAt: now, ways: ways)
        fetchTask = nil
        failureCount = 0
        lastError = nil
        nextAttempt = now.addingTimeInterval(configuration.minRequestInterval)
        onDataChanged?()
    }

    private func didFail(_ error: Error) {
        let now = clock()
        fetchTask = nil
        failureCount += 1
        let mapped = (error as? RoadDataError) ?? .transport
        lastError = mapped
        var backoff = min(configuration.maxBackoff,
                          configuration.minRequestInterval * pow(2, Double(failureCount - 1)))
        if case .rateLimited(let retryAfter) = mapped {
            backoff = max(backoff, min(retryAfter ?? 60, 300))
        }
        nextAttempt = now.addingTimeInterval(backoff)
        onDataChanged?()
    }
}
