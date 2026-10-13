import SwiftUI

@main
struct QipaiApp: App {
    @StateObject private var client = GameClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
        }
        .onChange(of: scenePhase) { phase in
            // 回到前台时自动重连
            if phase == .active && client.isLoggedIn && !client.wsConnected {
                client.connectWS()
            }
        }
    }
}
