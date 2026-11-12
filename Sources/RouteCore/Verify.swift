import Foundation

/// 事後核對用：描述「這筆指令做完，路由表應該長怎樣」。
public struct Expectation: Equatable {
    public enum Kind: Equatable { case added, removed }
    public let kind: Kind
    public let destination: String   // 正規化 CIDR
    public let gateway: String?      // 指定則要求閘道一致
    public let netif: String?        // 指定則要求介面一致

    public init(kind: Kind, destination: String, gateway: String? = nil, netif: String? = nil) {
        self.kind = kind; self.destination = destination; self.gateway = gateway; self.netif = netif
    }

    public var label: String {
        let via = gateway.map { " 經 \($0)" } ?? netif.map { " 介面 \($0)" } ?? ""
        return (kind == .added ? "新增 " : "刪除 ") + destination + via
    }

    func matches(_ e: RouteEntry) -> Bool {
        e.destination == destination && (gateway == nil || e.gatewayIP == gateway) && (netif == nil || e.netif == netif)
    }
}

public enum RouteVerifier {
    /// 回傳「沒達成」的期望：該新增的沒出現、該刪除的還在。
    public static func unmet(_ expectations: [Expectation], in entries: [RouteEntry]) -> [Expectation] {
        expectations.filter { ex in
            let present = entries.contains(where: ex.matches)
            return ex.kind == .added ? !present : present
        }
    }
}
