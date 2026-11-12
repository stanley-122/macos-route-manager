import SwiftUI
import RouteCore

struct MainView: View {
    @Environment(AppState.self) private var state
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("目前路由表").tag(0)
                Text("已存路由").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(10)
            if let w = state.systemWarning {
                Text("⚠︎ \(w)").font(.callout).foregroundStyle(.orange).padding(.vertical, 6)
            }
            Divider()
            if tab == 0 { RoutesTableView() } else { SavedRoutesView() }
        }
        .frame(minWidth: 760, minHeight: 440)
        .task { await state.refresh(); AppState.debugLog("main window appeared") }
    }
}

struct RoutesTableView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var showAll = false
    @State private var selection = Set<String>()

    private var rows: [RouteEntry] {
        state.entries.filter { e in
            (showAll || !e.isNoise) &&
            (search.isEmpty || [e.destination, e.gateway, e.flags, e.netif].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var deletable: [RouteEntry] { rows.filter { selection.contains($0.id) && state.canDelete($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("搜尋目的地、閘道、介面…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Toggle("顯示全部（含 link-local／multicast／主機快取）", isOn: $showAll)
                Spacer()
                Button("刪除選取（\(deletable.count)）") { let picked = deletable; Task { await state.deleteEntries(picked) } }
                    .disabled(deletable.isEmpty || state.busy)
                Button("重新整理") { Task { await state.refresh() } }
            }.padding(10)
            Table(rows, selection: $selection) {
                TableColumn("目的地") { e in Text(e.destination).monospaced().foregroundStyle(e.isDefault ? .blue : .primary) }
                TableColumn("閘道") { e in Text(e.gateway).monospaced() }
                TableColumn("旗標") { e in Text(e.flags).monospaced() }.width(min: 60, ideal: 80)
                TableColumn("介面") { e in Text(e.netif).monospaced() }.width(min: 60, ideal: 80)
            }
            .onChange(of: state.entries) { _, new in
                // 重新整理後，已不存在的選取一律清掉
                selection = selection.intersection(Set(new.map(\.id)))
            }
            Divider()
            HStack {
                Text(state.defaultSummary)
                Spacer()
                Text("顯示 \(rows.count) / \(state.entries.count) 筆　只有帶 S 旗標的手動靜態路由可刪；default、127/8、介面直連網段、預設閘道 /32 不可刪")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
}

struct SavedRoutesView: View {
    @Environment(AppState.self) private var state
    @State private var editing: SavedRoute?
    @State private var isNew = false
    @State private var selection: SavedRoute.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("新增") { isNew = true; editing = SavedRoute(name: "", destination: "", target: "") }
                Button("編輯") { if let r = state.saved.first(where: { $0.id == selection }) { isNew = false; editing = r } }
                    .disabled(selection == nil)
                Button("刪除") { if let r = state.saved.first(where: { $0.id == selection }) { state.deleteSaved(r); selection = nil } }
                    .disabled(selection == nil)
                Spacer()
                Button("全部套用") { Task { await state.apply(state.saved) } }.disabled(state.saved.isEmpty || state.busy)
                Button("全部移除") { Task { await state.remove(state.saved) } }.disabled(state.saved.isEmpty || state.busy || !state.system.reliable)
                Button("重新整理") { Task { await state.refresh() } }
            }.padding(10)
            Table(state.saved, selection: $selection) {
                TableColumn("狀態") { r in statusLabel(state.status(of: r)) }.width(70)
                TableColumn("名稱") { r in Text(r.name) }
                TableColumn("目的網段") { r in Text(r.destination).monospaced() }
                TableColumn("閘道／介面") { r in Text(r.target).monospaced() }
                TableColumn("備註") { r in Text(r.note).foregroundStyle(.secondary) }
                TableColumn("操作") { r in
                    let st = state.status(of: r)
                    HStack {
                        Button("套用") { Task { await state.apply([r]) } }.disabled(st != .inactive || state.busy)
                        Button("移除") { Task { await state.remove([r]) } }.disabled(!state.canRemove(r) || state.busy)
                    }
                }.width(130)
            }
            if state.saved.isEmpty {
                Text("尚無已存路由，按「新增」建立。").foregroundStyle(.secondary).padding()
            }
        }
        .sheet(item: $editing) { r in
            EditSheet(route: r, isNew: isNew) { saved in state.upsert(saved) }
        }
    }

    @ViewBuilder private func statusLabel(_ s: RouteStatus) -> some View {
        switch s {
        case .active: Label("生效", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .inactive: Label("未生效", systemImage: "circle").foregroundStyle(.secondary)
        case .system: Label("系統路由", systemImage: "lock.fill").foregroundStyle(.secondary)
        case .invalid: Label("無效", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

struct EditSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var route: SavedRoute
    let isNew: Bool
    let onSave: (SavedRoute) -> Void

    private var error: String? {
        let d = route.destination.trimmingCharacters(in: .whitespaces)
        let t = route.target.trimmingCharacters(in: .whitespaces)
        if d.isEmpty && t.isEmpty { return nil }
        return state.validate(destination: d, target: t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "新增已存路由" : "編輯已存路由").font(.headline)
            Form {
                TextField("名稱", text: $route.name)
                TextField("目的網段 CIDR", text: $route.destination, prompt: Text("例：10.20.60.0/24"))
                TextField("閘道 IP 或介面名", text: $route.target, prompt: Text("例：192.168.1.1 或 utun9"))
                TextField("備註", text: $route.note)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("儲存") {
                    var r = route
                    r.name = r.name.trimmingCharacters(in: .whitespaces)
                    r.destination = r.destination.trimmingCharacters(in: .whitespaces)
                    r.target = r.target.trimmingCharacters(in: .whitespaces)
                    onSave(r); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(route.name.trimmingCharacters(in: .whitespaces).isEmpty || route.destination.isEmpty || route.target.isEmpty || error != nil)
            }
        }
        .padding(20).frame(width: 440)
    }
}
