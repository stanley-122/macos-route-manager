import Foundation

public struct InterfaceAddress: Equatable {
    public let ip: String
    public let prefix: Int?
    public let peer: String?     // point-to-point（`inet A --> B`）
}

public struct InterfaceInfo: Equatable {
    public let name: String
    public var addresses: [InterfaceAddress]

    /// 直連網段（CIDR）。point-to-point 位址不算網段；/32 為本機位址自己的主機路由。
    public var connectedNetworks: [String] {
        addresses.compactMap { a in
            guard a.peer == nil, let p = a.prefix, let ip = IPv4.parse(a.ip) else { return nil }
            let c = CIDR(address: ip, prefix: p)
            return CIDR(address: c.first, prefix: p).description
        }
    }
}

public enum IfconfigParser {
    /// 解析 `/sbin/ifconfig` 輸出：介面名＋ inet 位址（netmask 為 0x 十六進位或點分）。
    public static func parse(_ text: String) -> [InterfaceInfo] {
        var out: [InterfaceInfo] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            guard let first = raw.first else { continue }
            if first != " " && first != "\t" {
                if let colon = raw.firstIndex(of: ":") {
                    let name = String(raw[..<colon])
                    if RouteValidator.isInterfaceNameSyntax(name) { out.append(InterfaceInfo(name: name, addresses: [])) }
                }
                continue
            }
            let t = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard t.count >= 2, t[0] == "inet", !out.isEmpty, IPv4.parse(t[1]) != nil else { continue }
            var peer: String?
            if let i = t.firstIndex(of: "-->"), i + 1 < t.count, IPv4.parse(t[i + 1]) != nil { peer = t[i + 1] }
            var prefix: Int?
            if let i = t.firstIndex(of: "netmask"), i + 1 < t.count { prefix = prefixLength(mask: t[i + 1]) }
            out[out.count - 1].addresses.append(InterfaceAddress(ip: t[1], prefix: prefix, peer: peer))
        }
        return out
    }

    /// 0xffffff00 或 255.255.255.0 → 24；非連續遮罩回傳 nil。
    public static func prefixLength(mask: String) -> Int? {
        var v: UInt32?
        if mask.hasPrefix("0x") || mask.hasPrefix("0X") { v = UInt32(mask.dropFirst(2), radix: 16) } else { v = IPv4.parse(mask) }
        guard let m = v else { return nil }
        let n = m.nonzeroBitCount
        let expected: UInt32 = n == 0 ? 0 : UInt32.max << UInt32(32 - n)
        return m == expected ? n : nil
    }
}

/// 系統自己建的路由：介面直連網段、介面本機位址的 /32、目前預設閘道 IP 的 /32，
/// 以及「閘道為 link#N 且目的網段包含該介面自己某個 inet 位址」的路由（不依賴 netmask）。
/// 資料來源讀不到或不完整時 reliable = false，此時一律不可刪（出錯時保守擋住）。
public struct SystemRouteSet: Equatable {
    public let destinations: Set<String>
    public let reliable: Bool
    private let ownAddresses: [String: [UInt32]]

    /// 尚未讀取／不可信：不可刪
    public static let empty = SystemRouteSet(destinations: [], reliable: false)

    public init(destinations: Set<String>, reliable: Bool = true) {
        self.destinations = destinations; self.reliable = reliable; self.ownAddresses = [:]
    }

    /// sourcesOK：netstat 與 ifconfig 是否都成功執行（結束碼 0）。
    /// 另外輸出解析後必須有路由列，且至少一個介面帶 inet，否則不可信。
    public init(entries: [RouteEntry], interfaces: [InterfaceInfo], sourcesOK: Bool = true) {
        var d = Set(interfaces.flatMap(\.connectedNetworks))
        var own: [String: [UInt32]] = [:]
        for i in interfaces {
            for a in i.addresses {
                guard let v = IPv4.parse(a.ip) else { continue }
                d.insert("\(a.ip)/32")   // 本機位址自己的 /32（系統也會建，帶 S 旗標）
                own[i.name, default: []].append(v)
            }
        }
        for e in entries where e.isDefault { if let g = e.gatewayIP { d.insert("\(g)/32") } }
        self.destinations = d
        self.ownAddresses = own
        // 至少要有一個非 loopback 介面帶 inet（lo0 永遠有 127.0.0.1，不能當作資料完整的證據）
        self.reliable = sourcesOK && !entries.isEmpty && own.keys.contains { !$0.hasPrefix("lo") }
    }

    public func contains(_ cidr: String) -> Bool { destinations.contains(cidr) }

    /// 第二道規則：link#N 路由且網段涵蓋該介面自己的位址。
    public func isLinkOwn(_ e: RouteEntry) -> Bool {
        guard e.gateway.hasPrefix("link#"), let c = try? RouteValidator.validateCIDR(e.destination),
              let mine = ownAddresses[e.netif] else { return false }
        return mine.contains { $0 >= c.first && $0 <= c.last }
    }

    public func isSystem(_ e: RouteEntry) -> Bool { contains(e.destination) || isLinkOwn(e) }

    /// 表格是否允許刪除：資料可信、基本條件成立、且不是系統路由。
    /// 旗標含 I（RTF_IFSCOPE，介面限定）的列一律不處理：要用 -ifscope 才碰得到。
    public func isDeletable(_ e: RouteEntry) -> Bool { reliable && e.isDeletable && !isSystem(e) && !e.flags.contains("I") }
}
