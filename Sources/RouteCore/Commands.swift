import Foundation

/// 指令字串只由「寫死的絕對路徑 + 驗證並重新格式化過的值」組成。
/// 使用者輸入的原字串不會進到結果：CIDR／IP 一律由解析出的數字重建。
public enum RouteCommandBuilder {
    public static let routePath = "/sbin/route"
    public static let failureMarker = "ROUTEMGR_FAILED"

    public static func addCommand(destination: String, target: String, knownInterfaces: Set<String>) throws -> String {
        let cidr = try RouteValidator.validateCIDR(destination)
        guard !cidr.isProtected else { throw RouteValidationError.protectedRoute(cidr.description) }
        switch try RouteValidator.validateTarget(target, knownInterfaces: knownInterfaces) {
        case .gateway(let g): return "\(routePath) -n add \(spec(cidr)) \(g)"
        case .interface(let i): return "\(routePath) -n add \(spec(cidr)) -interface \(i)"
        }
    }

    /// 刪除。gateway 與 interface 擇一（同時給會拒絕）；interface 必須語法合法且存在於 knownInterfaces。
    public static func deleteCommand(destination: String, gateway: String? = nil,
                                     interface: String? = nil, knownInterfaces: Set<String> = []) throws -> String {
        let cidr = try RouteValidator.validateCIDR(destination)
        guard !cidr.isProtected else { throw RouteValidationError.protectedRoute(cidr.description) }
        if let interface {
            guard gateway == nil else { throw RouteValidationError.badTarget("gateway+interface") }
            let i = try RouteValidator.validateInterface(interface, known: knownInterfaces)
            return "\(routePath) -n delete \(spec(cidr)) -interface \(i)"
        }
        if let gateway {
            guard let ip = IPv4.parse(gateway), ip != 0 else { throw RouteValidationError.badIPv4(gateway) }
            return "\(routePath) -n delete \(spec(cidr)) \(IPv4.format(ip))"
        }
        return "\(routePath) -n delete \(spec(cidr))"
    }

    /// 表格列的刪除指令：閘道為 IP 則帶閘道；閘道為 link#N 則帶 -interface <netif>（須存在於系統）。
    public static func deleteCommand(for e: RouteEntry, knownInterfaces: Set<String>) throws -> String {
        if let g = e.gatewayIP { return try deleteCommand(destination: e.destination, gateway: g) }
        return try deleteCommand(destination: e.destination, interface: e.netif, knownInterfaces: knownInterfaces)
    }

    /// /32 一律用 -host <ip>，其餘用 -net <CIDR>。
    static func spec(_ c: CIDR) -> String {
        c.prefix == 32 ? "-host \(IPv4.format(c.address))" : "-net \(c)"
    }

    /// 最後一道關：特權 shell 字串只准這些字元，且每段必須以 /sbin/route -n 開頭。
    static let allowed: Set<UInt8> = Set(
        Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /._-:;|&>[]".utf8))

    public static func isSafeCommand(_ cmd: String) -> Bool {
        cmd.hasPrefix("\(routePath) -n ") && cmd.utf8.allSatisfy { allowed.contains($0) }
            && !cmd.contains(";") && !cmd.contains("|") && !cmd.contains("&") && !cmd.contains(">")
    }

    /// 合成單一特權 shell 字串（一次授權）。失敗時印出固定標記，stderr 併入輸出。
    public static func script(for commands: [String]) throws -> String {
        guard !commands.isEmpty, commands.allSatisfy(isSafeCommand) else { throw RouteValidationError.unsafeScript }
        let s = commands.map { "\($0) 2>&1 || echo \(failureMarker)" }.joined(separator: "; ")
        guard s.utf8.allSatisfy({ allowed.contains($0) }) else { throw RouteValidationError.unsafeScript }
        return s
    }

    /// AppleScript 原始碼。script 內不應有引號或反斜線，仍照規則跳脫。
    public static func appleScript(for script: String) -> String {
        let esc = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(esc)\" with administrator privileges"
    }
}
