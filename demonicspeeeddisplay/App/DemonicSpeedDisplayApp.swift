//
//  DemonicSpeedDisplayApp.swift
//  Demonic Speed Display
//

import SwiftUI

@main
struct DemonicSpeedDisplayApp: App {
    @State private var settings: AppSettings
    @State private var model: DriveModel

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: DriveModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            DriveView()
                .environment(settings)
                .environment(model)
        }
    }
}
