import SwiftUI
import RouteCore

struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.defaultSummary)
        if let w = state.systemWarning { Text("⚠︎ \(w)") }
        Divider()
        if state.saved.isEmpty {
            Text("尚無已存路由")
        } else {
            ForEach(state.saved) { r in
                let st = state.status(of: r)
                Menu("\(mark(st)) \(r.name)　\(r.destination) → \(r.target)") {
                    Button("套用") { Task { await state.apply([r]) } }.disabled(st != .inactive || state.busy)
                    Button("移除") { Task { await state.remove([r]) } }.disabled(!state.canRemove(r) || state.busy)
                }
            }
            Divider()
            Button("全部套用") { Task { await state.apply(state.saved) } }.disabled(state.busy)
            Button("全部移除") { Task { await state.remove(state.saved) } }.disabled(state.busy || !state.system.reliable)
        }
        Divider()
        Button("開啟主視窗") {
            MainWindow.showDock()
            openWindow(id: MainWindow.id)
        }
        Button("重新整理") { Task { await state.refresh() } }
        Divider()
        Button("結束") { NSApplication.shared.terminate(nil) }
    }

    private func mark(_ s: RouteStatus) -> String {
        switch s { case .active: return "●"; case .inactive: return "○"; case .invalid: return "⚠︎"; case .system: return "◆" }
    }
}
