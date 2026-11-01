import SwiftUI

@main
struct HogarFinanzasApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environment(\.locale, Locale(identifier: "es_ES"))
                .task {
                    while !Task.isCancelled {
                        if scenePhase == .active { await store.synchronizeFamily() }
                        do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.synchronizeFamily() } } }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        #endif
    }
}
