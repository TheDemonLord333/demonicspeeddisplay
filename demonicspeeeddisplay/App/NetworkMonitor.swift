//
//  NetworkMonitor.swift
//  Demonic Speed Display
//

import Dispatch
import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    /// Ein NWPathMonitor lässt sich nach `cancel()` nicht neu starten; er läuft
    /// daher einmalig für die gesamte Lebensdauer der App.
    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = Self.makeHandler { [weak self] online in
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "DemonicSpeedDisplay.NetworkMonitor", qos: .utility))
    }

    nonisolated private static func makeHandler(
        _ sink: @escaping @Sendable (Bool) -> Void
    ) -> @Sendable (NWPath) -> Void {
        { path in sink(path.status == .satisfied) }
    }
}
