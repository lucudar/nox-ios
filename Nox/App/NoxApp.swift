import SwiftUI

@main
struct NoxApp: App {
    @State private var settings = AppSettings()
    @State private var servers = ServerStore()
    @State private var connection = ConnectionManager()
    @State private var stats = StatsStore()
    @State private var photo = BackgroundPhoto()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(servers)
                .environment(connection)
                .environment(stats)
                .environment(photo)
        }
    }
}
