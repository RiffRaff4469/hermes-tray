import SwiftUI

@main
@MainActor
struct HermesTrayApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            TrayContentView(store: store)
        } label: {
            Image(systemName: "waveform.path.ecg")
                .overlay(alignment: .topTrailing) {
                    if store.iconBusy {
                        Circle().fill(.orange).frame(width: 6, height: 6).offset(x: 3, y: -2)
                    }
                }
                .accessibilityLabel(store.iconBusy ? "Hermes is busy" : "Hermes is idle")
                .onAppear { store.start() }
        }
        .menuBarExtraStyle(.window)

        Window("HermesTray Settings", id: "settings") {
            SettingsView(store: store)
        }
        .defaultSize(width: 430, height: 210)
        .windowResizability(.contentSize)
    }
}
