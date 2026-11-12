import Foundation

public enum RouteValidationError: Error, LocalizedError, Equatable {
    case badIPv4(String)
    case badCIDR(String)
    case hostBitsSet(input: String, suggestion: String)
    case badInterfaceName(String)
    case unknownInterface(String)
    case badTarget(String)
    case protectedRoute(String)
    case unsafeScript

    public var errorDescription: String? {
        switch self {
        case .badIPv4(let s): return "不是有效的 IPv4 位址：\(Self.show(s))"
        case .badCIDR(let s): return "不是有效的 CIDR（例：10.20.60.0/24）：\(Self.show(s))"
        case .hostBitsSet(let input, let suggestion):
            return "主機位元不為 0：\(Self.show(input))。正確的網段應為 \(suggestion)"
        case .badInterfaceName(let s): return "介面名稱格式不符（只接受如 en0、utun9）：\(Self.show(s))"
        case .unknownInterface(let s): return "目前系統沒有這個介面：\(s)"
        case .badTarget(let s): return "閘道必須是 IPv4 位址或介面名稱：\(Self.show(s))"
        case .protectedRoute(let s): return "受保護的路由，禁止新增或刪除：\(s)（default 與 127/8）"
        case .unsafeScript: return "指令內容未通過安全檢查，已拒絕執行"
        }
    }

    private static func show(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\n", with: "\\n")
        return t.count > 40 ? String(t.prefix(40)) + "…" : t
    }
}

public struct CIDR: Equatable, Hashable, CustomStringConvertible {
    public let address: UInt32
    public let prefix: Int

    public var mask: UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }
    public var first: UInt32 { address & mask }
    public var last: UInt32 { address | ~mask }
    public var description: String { "\(IPv4.format(address))/\(prefix)" }

    /// 是否為 default（/0）或與 127/8 有任何重疊。
    public var isProtected: Bool {
        if prefix == 0 { return true }
        let loFirst: UInt32 = 127 << 24, loLast: UInt32 = (127 << 24) | 0x00FF_FFFF
        return first <= loLast && last >= loFirst
    }
}

public enum IPv4 {
    /// 純 ASCII 數字、1~3 位、不得有前導 0（避免八進位歧義）、0...255。
    static func octet(_ s: Substring) -> UInt32? {
        let b = Array(s.utf8)
        guard (1...3).contains(b.count), b.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        if b.count > 1 && b[0] == 48 { return nil }
        guard let v = UInt32(s), v <= 255 else { return nil }
        return v
    }

    public static func parse(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for p in parts {
            guard let o = octet(p) else { return nil }
            v = (v << 8) | o
        }
        return v
    }

    public static func format(_ v: UInt32) -> String {
        "\(v >> 24).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)"
    }
}

public enum RouteTarget: Equatable {
    case gateway(String)
    case interface(String)
}

public enum RouteValidator {
    /// 僅接受 ASCII 數字的整數（0...32 用）。
    static func prefixValue(_ s: Substring) -> Int? {
        let b = Array(s.utf8)
        guard (1...2).contains(b.count), b.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        if b.count > 1 && b[0] == 48 { return nil }
        guard let v = Int(s), v <= 32 else { return nil }
        return v
    }

    /// 嚴格 CIDR：a.b.c.d/p，主機位元必須為 0。
    public static func validateCIDR(_ s: String) throws -> CIDR {
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let addr = IPv4.parse(String(parts[0])),
              let p = prefixValue(parts[1]) else { throw RouteValidationError.badCIDR(s) }
        let c = CIDR(address: addr, prefix: p)
        if c.first != addr {
            throw RouteValidationError.hostBitsSet(input: s, suggestion: CIDR(address: c.first, prefix: p).description)
        }
        return c
    }

    /// 介面名稱格式：^[a-z]+[0-9]+$（手動掃描，不用 regex）。
    public static func isInterfaceNameSyntax(_ s: String) -> Bool {
        let b = Array(s.utf8)
        var i = 0
        while i < b.count, b[i] >= 97, b[i] <= 122 { i += 1 }
        guard i > 0 else { return false }
        let j = i
        while i < b.count, b[i] >= 48, b[i] <= 57 { i += 1 }
        return i > j && i == b.count
    }

    public static func validateInterface(_ s: String, known: Set<String>) throws -> String {
        guard isInterfaceNameSyntax(s) else { throw RouteValidationError.badInterfaceName(s) }
        guard known.contains(s) else { throw RouteValidationError.unknownInterface(s) }
        return s
    }

    /// 僅檢查語法（存檔時用，不要求介面此刻存在）。
    public static func validateTargetSyntax(_ s: String) throws -> RouteTarget {
        if let ip = IPv4.parse(s) {
            guard ip != 0 else { throw RouteValidationError.badTarget(s) }
            return .gateway(IPv4.format(ip))
        }
        if isInterfaceNameSyntax(s) { return .interface(s) }
        throw RouteValidationError.badTarget(s)
    }

    /// 組指令前用：語法 + 介面必須存在於系統。
    public static func validateTarget(_ s: String, knownInterfaces: Set<String>) throws -> RouteTarget {
        switch try validateTargetSyntax(s) {
        case .gateway(let g): return .gateway(g)
        case .interface(let i): return .interface(try validateInterface(i, known: knownInterfaces))
        }
    }

    /// 解析 `ifconfig -l` 的輸出，只留格式合法的介面名。
    public static func parseInterfaceList(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            .filter(isInterfaceNameSyntax))
    }
}
