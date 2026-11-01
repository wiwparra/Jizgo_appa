import SwiftUI

@main
struct HogarFinanzasApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environment(\.locale, Locale(identifier: "es_ES"))
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        #endif
    }
}
