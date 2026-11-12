import Foundation

public struct RouteEntry: Equatable, Identifiable, Hashable {
    /// 穩定 id：目的地＋閘道＋介面＋旗標（完全相同的重複列才加 #序號）
    public let id: String
    /// 正規化 CIDR，如 0.0.0.0/0、10.20.60.0/24、10.20.2.5/32
    public let destination: String
    public let gateway: String
    public let flags: String
    public let netif: String

    public init(destination: String, gateway: String, flags: String, netif: String, duplicateIndex: Int = 0) {
        self.destination = destination; self.gateway = gateway
        self.flags = flags; self.netif = netif
        let base = "\(destination)|\(gateway)|\(netif)|\(flags)"
        self.id = duplicateIndex > 0 ? "\(base)#\(duplicateIndex)" : base
    }

    public var isDefault: Bool { destination == "0.0.0.0/0" }
    public var gatewayIP: String? { IPv4.parse(gateway).map(IPv4.format) }

    private var cidr: CIDR? { try? RouteValidator.validateCIDR(destination) }
    public var isMulticast: Bool { guard let c = cidr else { return false }; let o = c.address >> 24; return o >= 224 && o < 240 }
    public var isLinkLocal: Bool { destination.hasPrefix("169.254.") }
    public var isBroadcast: Bool { destination == "255.255.255.255/32" }
    /// W = 動態複製的主機路由、L = ARP/鄰居快取
    public var isHostCache: Bool { flags.contains("W") || flags.contains("L") }
    public var isNoise: Bool { isMulticast || isLinkLocal || isBroadcast || isHostCache }

    /// 基本可刪條件：帶 S 旗標、非雜訊、非受保護。
    /// 系統自建的直連網段／預設閘道 /32 另由 SystemRouteSet 排除（旗標分不出來）。
    public var isDeletable: Bool {
        guard flags.contains("S"), !isNoise, let c = cidr else { return false }
        return !c.isProtected
    }
}

public enum NetstatParser {
    /// 把 netstat 的縮寫目的地正規化成 CIDR：default、10、10.20.60/24、192.168.1、4 段主機。
    public static func normalizeDestination(_ s: String) -> String? {
        if s == "default" { return "0.0.0.0/0" }
        var addr = Substring(s)
        var prefix: Int?
        if let slash = s.firstIndex(of: "/") {
            addr = s[..<slash]
            prefix = RouteValidator.prefixValue(s[s.index(after: slash)...])
            if prefix == nil { return nil }
        }
        let parts = addr.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var o: [UInt32] = []
        for p in parts { guard let v = IPv4.octet(p) else { return nil }; o.append(v) }
        let n = o.count
        while o.count < 4 { o.append(0) }
        let v = (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3]
        return "\(IPv4.format(v))/\(prefix ?? n * 8)"
    }

    public static func parse(_ text: String) -> [RouteEntry] {
        var out: [RouteEntry] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard t.count >= 4, t[0] != "Destination", let dest = normalizeDestination(t[0]) else { continue }
            guard t[2].utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }) else { continue }
            var e = RouteEntry(destination: dest, gateway: t[1], flags: t[2], netif: t[3])
            var n = 0
            while seen.contains(e.id) { n += 1; e = RouteEntry(destination: dest, gateway: t[1], flags: t[2], netif: t[3], duplicateIndex: n) }
            seen.insert(e.id)
            out.append(e)
        }
        return out
    }

    /// 預設閘道：優先取閘道為 IP 的 default，否則第一筆 default。
    public static func defaultGateway(in entries: [RouteEntry]) -> RouteEntry? {
        let d = entries.filter(\.isDefault)
        return d.first(where: { $0.gatewayIP != nil }) ?? d.first
    }
}
