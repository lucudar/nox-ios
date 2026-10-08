import SwiftUI
import UIKit

/// Navigation root: Home → Settings → sub-screens. Also wires persistence, statistics and
/// auto-connect, and applies the global tint / font / dark scheme.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ServerStore.self) private var servers
    @Environment(ConnectionManager.self) private var connection
    @Environment(StatsStore.self) private var stats
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [Route] = []
    @State private var launched = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(openSettings: { path.append(.settings) })
                .background(SwipeBackEnabler())
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .tint(settings.accentColor)
        .fontDesign(settings.fontDesign)
        .preferredColorScheme(.dark)
        .onChange(of: settings.look) { settings.persistLook() }
        .onChange(of: settings.prefs) { settings.persistPrefs() }
        .onChange(of: settings.userPresets) { settings.persistPresets() }
        .onChange(of: settings.rules) { settings.persistRules() }
        .onChange(of: settings.tunnelOptions) { _, options in
            connection.applyOptions(options)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stats.flush() }
        }
        .task {
            guard !launched else { return }
            launched = true
            connection.onTraffic = { [stats] down, up, seconds, server in
                stats.record(downMB: down, upMB: up, seconds: seconds, server: server)
            }
            connection.onLatency = { [stats] ms in
                stats.recordPing(ms)
            }
            // The tunnel may have kept running (or been started by iOS) while the app was closed.
            await connection.restore(servers: servers, options: settings.tunnelOptions)
            if settings.prefs.autoConnect, !connection.isActive, let server = servers.current {
                connection.connect(server, options: settings.tunnelOptions)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .settings: SettingsView()
        case .routing: RoutingView()
        case .routes: RoutesView()
        case .dns: DNSView()
        case .appearance: AppearanceView()
        case .language: LanguageView()
        case .stats: StatsView()
        case .logs: LogsView()
        }
    }
}

/// The navigation bar is hidden on every screen (custom back buttons), which also disables
/// UIKit's edge-swipe back gesture. This re-enables it without subclassing or extending
/// UINavigationController.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private let handler = Handler()

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        private func attach() {
            guard let navigation = navigationController,
                  let gesture = navigation.interactivePopGestureRecognizer else { return }
            handler.navigation = navigation
            gesture.delegate = handler
            gesture.isEnabled = true
        }
    }

    final class Handler: NSObject, UIGestureRecognizerDelegate {
        weak var navigation: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigation?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
