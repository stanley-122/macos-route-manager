import Foundation

public struct SavedRoute: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var destination: String   // CIDR
    public var target: String        // 閘道 IP 或介面名
    public var note: String

    enum CodingKeys: String, CodingKey { case id, name, destination, target, note }

    /// 容忍缺欄位：少了 note 等欄位不會讓整檔解碼失敗；缺 destination／target 者會在狀態上顯示「無效」。
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    public init(id: UUID = UUID(), name: String, destination: String, target: String, note: String = "") {
        self.id = id; self.name = name; self.destination = destination; self.target = target; self.note = note
    }
}

/// system：與系統路由（介面直連網段、預設閘道 /32）衝突，不可套用也不可移除
public enum RouteStatus: Equatable { case active, inactive, invalid, system }

public enum RouteMatcher {
    /// 以介面為目標的移除是否不會誤刪：同目的地只有一條，或多條中恰有一條介面相符。
    /// 現行路由表同目的地是否有任何 scoped（旗標含 I）的列。
    public static func hasScopedRoute(destination: String, in entries: [RouteEntry]) -> Bool {
        entries.contains { $0.destination == destination && $0.flags.contains("I") }
    }

    public static let scopedMessage = "此目的地有介面限定（scoped）路由，請改用終端機處理"

    /// 表格列是否可刪：系統規則通過，且同目的地沒有 scoped 路由。
    public static func canDeleteEntry(_ e: RouteEntry, in entries: [RouteEntry], system: SystemRouteSet) -> Bool {
        system.isDeletable(e) && !hasScopedRoute(destination: e.destination, in: entries)
    }

    public static func removalIsUnambiguous(destination: String, interface: String, in entries: [RouteEntry]) -> Bool {
        if hasScopedRoute(destination: destination, in: entries) { return false }
        let same = entries.filter { $0.destination == destination }
        if same.count <= 1 { return same.first?.netif == interface }
        return same.filter { $0.netif == interface }.count == 1
    }

    public static func status(of saved: SavedRoute, in entries: [RouteEntry], system: SystemRouteSet = .empty) -> RouteStatus {
        guard let c = try? RouteValidator.validateCIDR(saved.destination),
              let t = try? RouteValidator.validateTargetSyntax(saved.target) else { return .invalid }
        if system.contains(c.description) { return .system }
        if entries.contains(where: { $0.destination == c.description && system.isLinkOwn($0) }) { return .system }
        let hit = entries.contains { e in
            guard e.destination == c.description else { return false }
            switch t {
            case .gateway(let g): return e.gatewayIP == g
            case .interface(let i): return e.netif == i
            }
        }
        return hit ? .active : .inactive
    }
}

public final class RouteStore {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RouteManager/routes.json")
    }

    public init(url: URL = RouteStore.defaultURL) { self.url = url }

    /// 檔案不存在 → 空清單。解析失敗 → 丟錯（呼叫端決定如何處理，不會覆蓋原檔）。
    public func load() throws -> [SavedRoute] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        let routes = try JSONDecoder().decode([SavedRoute].self, from: data)
        // 缺 id 的項目已在解碼時配了新 UUID；回存一次讓它固定下來
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           raw.contains(where: { $0["id"] == nil }) {
            try? save(routes)   // 唯讀等原因寫不回去就算了：記憶體照用，不當成壞檔
        }
        return routes
    }

    public func save(_ routes: [SavedRoute]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(routes).write(to: url, options: .atomic)
    }

    /// 壞檔改名保留（不刪），回傳新路徑。
    @discardableResult
    public func quarantineCorruptFile() -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let dst = url.deletingLastPathComponent().appendingPathComponent("routes.json.corrupt-\(f.string(from: Date()))")
        return (try? FileManager.default.moveItem(at: url, to: dst)) != nil ? dst : nil
    }
}
