import Foundation
import AppKit
import Observation
import RouteCore

@MainActor
@Observable
final class AppState {
    var entries: [RouteEntry] = []
    var interfaces: Set<String> = []
    var system: SystemRouteSet = .empty
    var saved: [SavedRoute] = []
    var lastRefresh: Date?
    var busy = false

    private let store = RouteStore()
    nonisolated static let debug = ProcessInfo.processInfo.environment["ROUTEMGR_DEBUG"] != nil

    nonisolated static func debugLog(_ s: String) {
        if debug { FileHandle.standardError.write(Data("[RouteManager] \(s)\n".utf8)) }
    }

    init() {
        loadSaved()
        // 先讀一次，之後每 15 秒自動重新整理（netstat 很便宜），讓選單列狀態不過期
        Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                if !self.busy { await self.refresh() }
            }
        }
    }

    // MARK: 讀取

    var defaultRoute: RouteEntry? { NetstatParser.defaultGateway(in: entries) }

    var defaultSummary: String {
        guard let d = defaultRoute else { return "預設閘道：（無）" }
        let gw = d.gatewayIP ?? d.gateway
        return "預設閘道：\(gw)（\(d.netif)）"
    }

    func refresh() async {
        let (net, ifc) = await Task.detached { () -> (ShellResult, ShellResult) in
            (Shell.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]), Shell.run("/sbin/ifconfig", []))
        }.value
        entries = NetstatParser.parse(net.out)
        let infos = IfconfigParser.parse(ifc.out)
        interfaces = Set(infos.map(\.name))
        // 任一來源執行失敗（含啟動失敗，status = -1）、輸出空、或解析不到 inet 介面 → 不可信，禁止刪除
        system = SystemRouteSet(entries: entries, interfaces: infos, sourcesOK: net.ok && ifc.ok)
        lastRefresh = Date()
        Self.debugLog("routes=\(entries.count) interfaces=\(interfaces.count) system=\(system.destinations.count) \(defaultSummary)")
    }

    func status(of r: SavedRoute) -> RouteStatus { RouteMatcher.status(of: r, in: entries, system: system) }
    /// 資料不可信時的提示；尚未讀取過不顯示
    var systemWarning: String? {
        lastRefresh != nil && !system.reliable ? "讀不到介面資訊，暫停刪除功能" : nil
    }
    func canRemove(_ r: SavedRoute) -> Bool { system.reliable && status(of: r) == .active }
    func canDelete(_ e: RouteEntry) -> Bool { RouteMatcher.canDeleteEntry(e, in: entries, system: system) }

    // MARK: 已存路由

    func loadSaved() {
        do { saved = try store.load() } catch {
            let moved = store.quarantineCorruptFile()
            saved = []
            showError("routes.json 無法解析，已改名保留為：\(moved?.lastPathComponent ?? "（改名失敗）")，並以空清單啟動。\n\(error.localizedDescription)")
        }
    }

    func persist() {
        do { try store.save(saved) } catch { showError("儲存失敗：\(error.localizedDescription)") }
    }

    /// 存檔前驗證（語法 + 非保護）。回傳錯誤訊息或 nil。
    func validate(destination: String, target: String) -> String? {
        do {
            let c = try RouteValidator.validateCIDR(destination)
            guard !c.isProtected else { throw RouteValidationError.protectedRoute(c.description) }
            _ = try RouteValidator.validateTargetSyntax(target)
            return nil
        } catch { return error.localizedDescription }
    }

    func upsert(_ r: SavedRoute) {
        if let i = saved.firstIndex(where: { $0.id == r.id }) { saved[i] = r } else { saved.append(r) }
        persist()
    }

    func deleteSaved(_ r: SavedRoute) {
        saved.removeAll { $0.id == r.id }
        persist()
    }

    // MARK: 改路由（需管理員）

    private struct Plan { let command: String; let expectation: Expectation }

    func apply(_ routes: [SavedRoute]) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        await refresh()
        var plans: [Plan] = []
        var skipped: [String] = []
        for r in routes {
            switch status(of: r) {
            case .active: continue
            case .system: skipped.append("\(r.name)：與系統路由（介面直連網段或預設閘道）衝突")
            case .invalid: skipped.append("\(r.name)：欄位無效")
            case .inactive:
                do {
                    let cmd = try RouteCommandBuilder.addCommand(destination: r.destination, target: r.target, knownInterfaces: interfaces)
                    let cidr = try RouteValidator.validateCIDR(r.destination).description
                    var gw: String?, nif: String?
                    switch try RouteValidator.validateTarget(r.target, knownInterfaces: interfaces) {
                    case .gateway(let g): gw = g
                    case .interface(let i): nif = i
                    }
                    plans.append(Plan(command: cmd, expectation: Expectation(kind: .added, destination: cidr, gateway: gw, netif: nif)))
                } catch { skipped.append("\(r.name)：\(error.localizedDescription)") }
            }
        }
        await run(plans, title: "套用路由", skipped: skipped, nothing: "沒有需要套用的路由（都已生效）。")
    }

    func remove(_ routes: [SavedRoute]) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        await refresh()   // 按下當下重讀，不用快取
        guard system.reliable else { showInfo(systemWarning ?? "讀不到介面資訊，暫停刪除功能"); return }
        var plans: [Plan] = []
        var skipped: [String] = []
        for r in routes {
            switch status(of: r) {
            case .inactive: continue
            case .system: skipped.append("\(r.name)：系統路由，不可移除")
            case .invalid: skipped.append("\(r.name)：欄位無效")
            case .active:
                do {
                    let cidr = try RouteValidator.validateCIDR(r.destination).description
                    var gw: String?, nif: String?
                    switch try RouteValidator.validateTargetSyntax(r.target) {
                    case .gateway(let g): gw = g
                    case .interface(let i): nif = i
                    }
                    if RouteMatcher.hasScopedRoute(destination: cidr, in: entries) {
                        skipped.append("\(r.name)：\(RouteMatcher.scopedMessage)")
                        continue
                    }
                    if let nif, !RouteMatcher.removalIsUnambiguous(destination: cidr, interface: nif, in: entries) {
                        skipped.append("\(r.name)：\(cidr) 在路由表有多條，無法確定刪哪一條，請到「目前路由表」頁手動處理")
                        continue
                    }
                    let cmd = try RouteCommandBuilder.deleteCommand(destination: r.destination, gateway: gw,
                                                                    interface: nif, knownInterfaces: interfaces)
                    plans.append(Plan(command: cmd, expectation: Expectation(kind: .removed, destination: cidr, gateway: gw, netif: nif)))
                } catch { skipped.append("\(r.name)：\(error.localizedDescription)") }
            }
        }
        await run(plans, title: "移除路由", skipped: skipped, nothing: "沒有需要移除的路由（都未生效）。")
    }

    /// 刪除目前路由表的列。先重讀 netstat／ifconfig，再以 id 對回最新的列判斷與組指令；
    /// 確認框顯示與實際送出的是同一份指令。
    func deleteEntries(_ picked: [RouteEntry]) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        await refresh()
        guard system.reliable else { showInfo(systemWarning ?? "讀不到介面資訊，暫停刪除功能"); return }
        var plans: [Plan] = []
        var skipped: [String] = []
        for old in picked {
            guard let e = entries.first(where: { $0.id == old.id }) else { skipped.append("\(old.destination)：路由表已變動，這一列已不存在"); continue }
            if RouteMatcher.hasScopedRoute(destination: e.destination, in: entries) { skipped.append("\(e.destination)：\(RouteMatcher.scopedMessage)"); continue }
            guard system.isDeletable(e) else { skipped.append("\(e.destination)：不可刪除（系統路由或非靜態）"); continue }
            do {
                let cmd = try RouteCommandBuilder.deleteCommand(for: e, knownInterfaces: interfaces)
                plans.append(Plan(command: cmd, expectation: Expectation(kind: .removed, destination: e.destination,
                                                                          gateway: e.gatewayIP, netif: e.gatewayIP == nil ? e.netif : nil)))
            } catch { skipped.append("\(e.destination)：\(error.localizedDescription)") }
        }
        await run(plans, title: "刪除路由", skipped: skipped, nothing: "沒有可刪除的路由。")
    }

    private func run(_ plans: [Plan], title: String, skipped: [String], nothing: String) async {
        let skipText = skipped.isEmpty ? "" : "略過 \(skipped.count) 筆：\n" + skipped.map { "- \($0)" }.joined(separator: "\n")
        guard !plans.isEmpty else { showInfo(skipped.isEmpty ? nothing : skipText); return }
        let ran = await execute(plans)
        if ran && !skipped.isEmpty { showInfo("已執行其餘路由。\n\(skipText)") }

        func execute(_ plans: [Plan]) async -> Bool {
            let commands = plans.map(\.command)
            let script: String
            do { script = try RouteCommandBuilder.script(for: commands) } catch { showError(error.localizedDescription); return false }
            guard confirm(title: title, commands: commands) else { return false }
            let result = await Task.detached { PrivilegedRunner.run(script: script) }.value
            var out = ""
            switch result {
            case .canceled: return false   // 使用者取消授權：靜默返回
            case .failure(let e): showError(e.isEmpty ? "指令執行失敗" : e); await refresh(); return true
            case .output(let o): out = o
            }
            // 不只靠 exit code：一律重讀路由表核對
            await refresh()
            let unmet = RouteVerifier.unmet(plans.map(\.expectation), in: entries)
            if !unmet.isEmpty || out.contains(RouteCommandBuilder.failureMarker) {
                var msg = unmet.isEmpty ? "指令回報失敗，但事後核對路由表沒有發現差異。" : "事後核對：以下 \(unmet.count) 筆沒有成功：\n" + unmet.map { "- \($0.label)" }.joined(separator: "\n")
                msg += "\n\n指令輸出：\n" + (out.isEmpty ? "（無）" : out)
                showError(msg)
            } else { Self.debugLog("verified ok: \(plans.count) 筆") }
            return true
        }
    }

    // MARK: 對話框

    private func confirm(title: String, commands: [String]) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "\(title)：將以管理員權限執行以下指令"
        a.informativeText = commands.joined(separator: "\n")
        a.addButton(withTitle: "執行")
        a.addButton(withTitle: "取消")
        return a.runModal() == .alertFirstButtonReturn
    }

    func showError(_ msg: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.alertStyle = .warning; a.messageText = "發生錯誤"; a.informativeText = msg
        a.runModal()
    }

    func showInfo(_ msg: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = msg; a.runModal()
    }
}
