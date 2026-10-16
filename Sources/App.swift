import SwiftUI

@main
struct NextChargeApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("NextCharge", id: "main") {
            MainView()
                .environmentObject(store)
                .onAppear { store.requestNotificationPermission() }
        }
        .defaultSize(width: 860, height: 580)

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(systemName: "creditcard")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
