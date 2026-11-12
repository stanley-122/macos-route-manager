import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 主視窗關閉後隱藏 Dock 圖示，App 留在選單列
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, w.title == MainWindow.title else { return }
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum MainWindow {
    static let title = "路由管理"
    static let id = "main"
    @MainActor static func showDock() {
        let title = MainWindow.title
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 視窗剛建立時可能還沒進 NSApp.windows，稍後再拉到最前
        for delay in [0.0, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.title == title }?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@main
struct RouteManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        Window(MainWindow.title, id: MainWindow.id) {
            MainView()
                .environment(state)
                .onAppear { MainWindow.showDock() }
        }
        .defaultSize(width: 900, height: 560)

        MenuBarExtra("路由管理", systemImage: "arrow.triangle.branch") {
            MenuContent().environment(state)
        }
        .menuBarExtraStyle(.menu)
    }
}
