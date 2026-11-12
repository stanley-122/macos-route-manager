import XCTest
@testable import RouteCore

final class ParserTests: XCTestCase {
    func fixture() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/netstat-local.txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testRealFixture() throws {
        let es = NetstatParser.parse(try fixture())
        let expected: [(String, String, String, String)] = [
            ("0.0.0.0/0", "192.168.88.1", "UGScg", "en0"),
            ("0.0.0.0/0", "link#40", "UCSIg", "utun9"),
            ("10.20.1.0/24", "link#40", "UCS", "utun9"),
            ("10.20.2.0/24", "link#40", "UCS", "utun9"),
            ("10.20.2.200/32", "link#40", "UCS", "utun9"),
            ("10.20.10.61/32", "link#40", "UCS", "utun9"),
            ("10.20.60.0/24", "link#40", "UCS", "utun9"),
            ("100.64.0.0/10", "link#40", "UCS", "utun9"),
            ("100.100.10.21/32", "link#40", "UHWIi", "utun9"),
            ("100.100.100.100/32", "link#40", "UCS", "utun9"),
            ("100.100.100.100/32", "link#40", "UHWIi", "utun9"),
            ("100.100.10.22/32", "link#40", "UHWIi", "utun9"),
            ("100.100.10.20/32", "100.100.10.20", "UH", "utun9"),
            ("127.0.0.0/8", "127.0.0.1", "UCS", "lo0"),
            ("127.0.0.1/32", "127.0.0.1", "UH", "lo0"),
            ("169.254.0.0/16", "link#17", "UCS", "en0"),
            ("192.168.88.0/28", "link#17", "UCS", "en0"),
            ("192.168.88.1/32", "link#17", "UCS", "en0"),
            ("192.168.88.1/32", "2:0:0:0:0:1", "UHLWIir", "en0"),
            ("192.168.88.2/32", "link#17", "UCS", "en0"),
            ("192.168.88.2/32", "2:0:0:0:0:2", "UHLWI", "lo0"),
            ("192.168.88.15/32", "ff:ff:ff:ff:ff:ff", "UHLWbI", "en0"),
            ("172.16.60.0/24", "link#40", "UCS", "utun9"),
            ("172.16.60.1/32", "link#40", "UHWIi", "utun9"),
            ("172.16.61.0/24", "link#40", "UCS", "utun9"),
            ("172.16.254.0/24", "link#40", "UCS", "utun9"),
            ("172.16.254.100/32", "link#40", "UHWIi", "utun9"),
            ("224.0.0.0/4", "link#17", "UmCS", "en0"),
            ("224.0.0.0/4", "link#40", "UmCSI", "utun9"),
            ("224.0.0.251/32", "1:0:5e:0:0:fb", "UHmLWI", "en0"),
            ("239.255.255.250/32", "1:0:5e:7f:ff:fa", "UHmLWI", "en0"),
            ("255.255.255.255/32", "link#17", "UCS", "en0"),
            ("255.255.255.255/32", "link#40", "UCSI", "utun9")
        ]
        XCTAssertEqual(es.count, expected.count)
        for (e, x) in zip(es, expected) {
            XCTAssertEqual(e.destination, x.0); XCTAssertEqual(e.gateway, x.1)
            XCTAssertEqual(e.flags, x.2); XCTAssertEqual(e.netif, x.3)
        }
        XCTAssertEqual(Set(es.map(\.id)).count, es.count, "id 必須唯一")
        XCTAssertEqual(NetstatParser.defaultGateway(in: es)?.gateway, "192.168.88.1")
    }

    func testStableIdAndDuplicates() {
        let t = "Destination Gateway Flags Netif\n10.20.60/24 1.1.1.1 UGSc en0\n10.20.60/24 1.1.1.1 UGSc en0\n"
        let a = NetstatParser.parse(t)
        XCTAssertEqual(a[0].id, "10.20.60.0/24|1.1.1.1|en0|UGSc")
        XCTAssertNotEqual(a[0].id, a[1].id)
        // 列序改變不影響 id
        let b = NetstatParser.parse("Destination Gateway Flags Netif\n10.9.9/24 2.2.2.2 UGSc en1\n" + t.split(separator: "\n").dropFirst().joined(separator: "\n"))
        XCTAssertEqual(b[1].id, a[0].id)
    }

    func testAbbreviations() {
        let n = NetstatParser.normalizeDestination
        XCTAssertEqual(n("default"), "0.0.0.0/0")
        XCTAssertEqual(n("10"), "10.0.0.0/8")
        XCTAssertEqual(n("10.20.60/24"), "10.20.60.0/24")
        XCTAssertEqual(n("192.168.1"), "192.168.1.0/24")
        XCTAssertEqual(n("169.254"), "169.254.0.0/16")
        XCTAssertEqual(n("100.64/10"), "100.64.0.0/10")
        XCTAssertEqual(n("127"), "127.0.0.0/8")
        XCTAssertEqual(n("10.20.2.5"), "10.20.2.5/32")
        XCTAssertEqual(n("192.168.88.1/32"), "192.168.88.1/32")
        XCTAssertEqual(n("224.0.0/4"), "224.0.0.0/4")
        XCTAssertNil(n("link#40"))
        XCTAssertNil(n("10.20.60/33"))
        XCTAssertNil(n("1.2.3.4.5"))
        XCTAssertNil(n("256"))
    }

    func testSyntheticSample() {
        let text = """
        Routing tables

        Internet:
        Destination        Gateway            Flags               Netif Expire
        default            192.168.1.1        UGScg                 en0
        10.20.60/24         10.1.1.1           UGSc                  en0
        192.168.1          link#6             UCS                   en0      !
        192.168.1.7        aa:bb:cc:d:e:f     UHLWIi                en0   1180
        224.0.0/4          link#6             UmCS                  en0      !
        """
        let es = NetstatParser.parse(text)
        XCTAssertEqual(es.count, 5)
        XCTAssertEqual(es[1], RouteEntry(destination: "10.20.60.0/24", gateway: "10.1.1.1", flags: "UGSc", netif: "en0"))
        XCTAssertTrue(es[0].isDefault); XCTAssertFalse(es[0].isDeletable)
        XCTAssertTrue(es[1].isDeletable)
        XCTAssertTrue(es[3].isNoise); XCTAssertTrue(es[4].isNoise)
        XCTAssertEqual(NetstatParser.defaultGateway(in: es)?.gateway, "192.168.1.1")
    }

    func testProtectedNotDeletable() {
        XCTAssertFalse(RouteEntry(destination: "127.0.0.0/8", gateway: "127.0.0.1", flags: "UCS", netif: "lo0").isDeletable)
    }
}

final class ValidationTests: XCTestCase {
    let ifs: Set<String> = ["en0", "utun9", "lo0"]

    func testCIDRValid() throws {
        XCTAssertEqual(try RouteValidator.validateCIDR("10.20.60.0/24").description, "10.20.60.0/24")
        XCTAssertEqual(try RouteValidator.validateCIDR("192.168.1.5/32").description, "192.168.1.5/32")
        XCTAssertEqual(try RouteValidator.validateCIDR("0.0.0.0/0").description, "0.0.0.0/0")
    }

    func testHostBitsRejectedWithSuggestion() {
        XCTAssertThrowsError(try RouteValidator.validateCIDR("10.20.60.5/24")) { e in
            XCTAssertEqual(e as? RouteValidationError, .hostBitsSet(input: "10.20.60.5/24", suggestion: "10.20.60.0/24"))
        }
    }

    func testBadInputsRejected() {
        let bad = ["", "10.20.60.0", "10.20.60.0/33", "10.20.60.0/-1", "256.1.1.1/24", "1.1.1/24", "1.1.1.1.1/24",
                   "01.1.1.1/24", "1.1.1.1/024", "1.1.1.1/", "/24", "a.b.c.d/8", "1.1.1.1/2/3",
                   "1.1.1.1; rm -rf /", "1.1.1.1/24; rm -rf /", "$(id)/24", "`id`/24", "1.1.1.1/24 ",
                   " 1.1.1.1/24", "1.1.1.1 /24", "1.1.1.1/24\nrm", "1.1.1.1/24\n", "1.1.1.1/2 4", "１.1.1.1/24",
                   "1.1.1.1/24|id", "1.1.1.1/24&&id", "1.1.1.1/24>x"]
        for s in bad { XCTAssertThrowsError(try RouteValidator.validateCIDR(s), "應拒絕：\(s)") }
    }

    func testInterfaceRules() throws {
        XCTAssertEqual(try RouteValidator.validateInterface("en0", known: ifs), "en0")
        XCTAssertThrowsError(try RouteValidator.validateInterface("en9", known: ifs))   // 不存在
        for s in ["", "en", "0", "EN0", "en0 ", "en0;id", "$(id)", "`id`", "en0\n", "en 0", "en-0", "utun9&", "en0a", "../en0"] {
            XCTAssertThrowsError(try RouteValidator.validateInterface(s, known: ifs.union([s])), "應拒絕：\(s)")
        }
    }

    func testTarget() throws {
        XCTAssertEqual(try RouteValidator.validateTarget("192.168.1.1", knownInterfaces: ifs), .gateway("192.168.1.1"))
        XCTAssertEqual(try RouteValidator.validateTarget("utun9", knownInterfaces: ifs), .interface("utun9"))
        for s in ["0.0.0.0", "1.1.1.1;id", "$(id)", "`id`", "1.1.1.1 2.2.2.2", "en0\nid", "", " "] {
            XCTAssertThrowsError(try RouteValidator.validateTarget(s, knownInterfaces: ifs), "應拒絕：\(s)")
        }
    }

    func testProtected() {
        for c in ["0.0.0.0/0", "127.0.0.0/8", "127.0.0.1/32", "127.1.0.0/16", "0.0.0.0/1", "112.0.0.0/4"] {
            XCTAssertTrue(try RouteValidator.validateCIDR(c).isProtected, c)
            XCTAssertThrowsError(try RouteCommandBuilder.addCommand(destination: c, target: "10.0.0.1", knownInterfaces: ifs), c)
            XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: c), c)
        }
        XCTAssertFalse(try RouteValidator.validateCIDR("128.0.0.0/1").isProtected)
        XCTAssertFalse(try RouteValidator.validateCIDR("126.0.0.0/8").isProtected)
    }

    func testInterfaceListParse() {
        XCTAssertEqual(RouteValidator.parseInterfaceList("lo0 gif0 en0 bridge0 utun9\n"), ["lo0", "gif0", "en0", "bridge0", "utun9"])
    }
}

final class CommandTests: XCTestCase {
    let ifs: Set<String> = ["en0", "utun9"]

    func testAdd() throws {
        XCTAssertEqual(try RouteCommandBuilder.addCommand(destination: "10.20.60.0/24", target: "192.168.1.1", knownInterfaces: ifs),
                       "/sbin/route -n add -net 10.20.60.0/24 192.168.1.1")
        XCTAssertEqual(try RouteCommandBuilder.addCommand(destination: "10.20.60.7/32", target: "192.168.1.1", knownInterfaces: ifs),
                       "/sbin/route -n add -host 10.20.60.7 192.168.1.1")
        XCTAssertEqual(try RouteCommandBuilder.addCommand(destination: "10.20.60.7/32", target: "utun9", knownInterfaces: ifs),
                       "/sbin/route -n add -host 10.20.60.7 -interface utun9")
        XCTAssertEqual(try RouteCommandBuilder.addCommand(destination: "10.20.60.0/24", target: "utun9", knownInterfaces: ifs),
                       "/sbin/route -n add -net 10.20.60.0/24 -interface utun9")
    }

    func testDelete() throws {
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24"), "/sbin/route -n delete -net 10.20.60.0/24")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24", gateway: "1.2.3.4"),
                       "/sbin/route -n delete -net 10.20.60.0/24 1.2.3.4")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.7/32"), "/sbin/route -n delete -host 10.20.60.7")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.7/32", gateway: "1.2.3.4"),
                       "/sbin/route -n delete -host 10.20.60.7 1.2.3.4")
        XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24", gateway: "1.2.3.4;id"))
    }

    func testInjectionNeverBuilds() {
        let evil = ["1.1.1.1; rm -rf /", "$(id)", "`id`", "1.1.1.1 && id", "1.1.1.1\nid", "en0; id", "1.1.1.1 -interface en0"]
        for e in evil {
            XCTAssertThrowsError(try RouteCommandBuilder.addCommand(destination: "10.0.0.0/24", target: e, knownInterfaces: ifs), e)
            XCTAssertThrowsError(try RouteCommandBuilder.addCommand(destination: e, target: "10.0.0.1", knownInterfaces: ifs), e)
            XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: e), e)
            XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: "10.0.0.0/24", gateway: e), e)
        }
    }

    func testScript() throws {
        let a = "/sbin/route -n add -net 10.20.60.0/24 1.2.3.4"
        let b = "/sbin/route -n delete -net 10.0.61.0/24"
        XCTAssertEqual(try RouteCommandBuilder.script(for: [a, b]),
                       "\(a) 2>&1 || echo ROUTEMGR_FAILED; \(b) 2>&1 || echo ROUTEMGR_FAILED")
        XCTAssertThrowsError(try RouteCommandBuilder.script(for: []))
        XCTAssertThrowsError(try RouteCommandBuilder.script(for: ["/bin/rm -rf /"]))
        XCTAssertThrowsError(try RouteCommandBuilder.script(for: [a + "; id"]))
        XCTAssertThrowsError(try RouteCommandBuilder.script(for: [a + " $(id)"]))
    }

    func testMarkerHasNoGlobChars() {
        XCTAssertTrue(RouteCommandBuilder.failureMarker.allSatisfy { $0.isLetter || $0 == "_" })
    }

    func testAppleScriptWrap() {
        XCTAssertEqual(RouteCommandBuilder.appleScript(for: "/sbin/route -n x"),
                       "do shell script \"/sbin/route -n x\" with administrator privileges")
        XCTAssertTrue(RouteCommandBuilder.appleScript(for: "a\"b\\c").contains("a\\\"b\\\\c"))
    }
}

final class StoreTests: XCTestCase {
    func testRoundTripAndStatus() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RouteStore(url: dir.appendingPathComponent("sub/routes.json"))
        XCTAssertEqual(try store.load(), [])
        let r = SavedRoute(name: "客戶 A", destination: "10.20.60.0/24", target: "192.168.1.1", note: "備註；$(id)")
        try store.save([r])
        XCTAssertEqual(try store.load(), [r])

        let es = NetstatParser.parse("Destination Gateway Flags Netif\n10.20.60/24 192.168.1.1 UGSc en0\n")
        XCTAssertEqual(RouteMatcher.status(of: r, in: es), .active)
        var other = r; other.target = "192.168.1.2"
        XCTAssertEqual(RouteMatcher.status(of: other, in: es), .inactive)
        var viaIf = r; viaIf.target = "en0"
        XCTAssertEqual(RouteMatcher.status(of: viaIf, in: es), .active)
        var bad = r; bad.destination = "x"
        XCTAssertEqual(RouteMatcher.status(of: bad, in: es), .invalid)
    }

    func testCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("routes.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let store = RouteStore(url: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertNotNil(store.quarantineCorruptFile())
        XCTAssertEqual(try store.load(), [])
    }
}

final class InterfaceTests: XCTestCase {
    func testPrefixLength() {
        XCTAssertEqual(IfconfigParser.prefixLength(mask: "0xffffff00"), 24)
        XCTAssertEqual(IfconfigParser.prefixLength(mask: "0xfffffff0"), 28)
        XCTAssertEqual(IfconfigParser.prefixLength(mask: "0xffffffff"), 32)
        XCTAssertEqual(IfconfigParser.prefixLength(mask: "0xff000000"), 8)
        XCTAssertEqual(IfconfigParser.prefixLength(mask: "0x00000000"), 0)
        XCTAssertEqual(IfconfigParser.prefixLength(mask: "255.255.255.0"), 24)
        XCTAssertNil(IfconfigParser.prefixLength(mask: "0xff00ff00"))
        XCTAssertNil(IfconfigParser.prefixLength(mask: "0xzz"))
        XCTAssertNil(IfconfigParser.prefixLength(mask: ""))
    }

    func testParseSynthetic() {
        let t = """
        en0: flags=8863<UP> mtu 1500
        \tinet 192.168.1.37 netmask 0xffffff00 broadcast 192.168.1.255
        \tinet6 fe80::1 prefixlen 64
        utun9: flags=8051<UP,POINTOPOINT> mtu 1280
        \tinet 100.100.10.20 --> 100.100.10.20 netmask 0xffffffff
        ppp0: flags=8051<UP,POINTOPOINT> mtu 1280
        \tinet 10.9.9.2 --> 10.9.9.1 netmask 0xffffff00
        en5: flags=8863<UP> mtu 1500
        \tinet 10.1.1.5 netmask 0xff00ff00
        lo0: flags=8049<UP> mtu 16384
        \tinet 127.0.0.1 netmask 0xff000000
        """
        let i = IfconfigParser.parse(t)
        XCTAssertEqual(i.map(\.name), ["en0", "utun9", "ppp0", "en5", "lo0"])
        XCTAssertEqual(i[0].connectedNetworks, ["192.168.1.0/24"])
        XCTAssertEqual(i[1].addresses.first?.peer, "100.100.10.20")
        XCTAssertEqual(i[1].connectedNetworks, [])      // point-to-point 不當成直連網段
        XCTAssertEqual(i[2].connectedNetworks, [])      // 即使遮罩不是 /32
        XCTAssertEqual(i[3].connectedNetworks, [])      // 非連續遮罩
        XCTAssertEqual(i[4].connectedNetworks, ["127.0.0.0/8"])
    }

    func testRealFixtureSystemRoutes() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let ifs = IfconfigParser.parse(try String(contentsOf: dir.appendingPathComponent("ifconfig-local.txt"), encoding: .utf8))
        let es = NetstatParser.parse(try String(contentsOf: dir.appendingPathComponent("netstat-local.txt"), encoding: .utf8))
        let sys = SystemRouteSet(entries: es, interfaces: ifs)
        XCTAssertEqual(sys.destinations, ["127.0.0.0/8", "127.0.0.1/32", "192.168.88.0/28", "192.168.88.1/32", "192.168.88.2/32", "100.100.10.20/32"])
        // 192.168.88/28（UCS，S 旗標）與預設閘道 /32 不可刪
        let lan = es.first { $0.destination == "192.168.88.0/28" }!
        XCTAssertTrue(lan.isDeletable); XCTAssertFalse(sys.isDeletable(lan))
        let gw = es.first { $0.destination == "192.168.88.1/32" && $0.flags == "UCS" }!
        XCTAssertFalse(sys.isDeletable(gw))
        // 使用者經 VPN 介面加的路由仍可刪
        let vpn = es.first { $0.destination == "10.20.60.0/24" }!
        XCTAssertTrue(sys.isDeletable(vpn))
        XCTAssertFalse(sys.isDeletable(es.first { $0.isDefault }!))
    }

    func testSavedRouteSystemStatus() {
        let es = NetstatParser.parse("Destination Gateway Flags Netif\n192.168.88/28 link#17 UCS en0\n10.20.60/24 1.1.1.1 UGSc en0\n")
        let sys = SystemRouteSet(destinations: ["192.168.88.0/28"])
        let a = SavedRoute(name: "a", destination: "192.168.88.0/28", target: "en0")
        XCTAssertEqual(RouteMatcher.status(of: a, in: es, system: sys), .system)
        let b = SavedRoute(name: "b", destination: "10.20.60.0/24", target: "1.1.1.1")
        XCTAssertEqual(RouteMatcher.status(of: b, in: es, system: sys), .active)
    }
}

final class VerifyTests: XCTestCase {
    func testUnmet() {
        let es = NetstatParser.parse("Destination Gateway Flags Netif\n10.20.60/24 1.1.1.1 UGSc en0\n10.0.61/24 link#9 UCS utun9\n")
        let ok = [Expectation(kind: .added, destination: "10.20.60.0/24", gateway: "1.1.1.1"),
                  Expectation(kind: .removed, destination: "10.0.62.0/24"),
                  Expectation(kind: .added, destination: "10.0.61.0/24", netif: "utun9")]
        XCTAssertEqual(RouteVerifier.unmet(ok, in: es), [])
        let bad = [Expectation(kind: .added, destination: "10.20.60.0/24", gateway: "9.9.9.9"),   // 閘道不符
                   Expectation(kind: .added, destination: "10.0.99.0/24"),                        // 沒出現
                   Expectation(kind: .removed, destination: "10.20.60.0/24", gateway: "1.1.1.1"),  // 還在
                   Expectation(kind: .removed, destination: "10.20.60.0/24", gateway: "2.2.2.2")]  // 已不在（成功）
        XCTAssertEqual(RouteVerifier.unmet(bad, in: es), Array(bad.prefix(3)))
        XCTAssertEqual(bad[0].label, "新增 10.20.60.0/24 經 9.9.9.9")
    }

    func testDecodeToleratesMissingFields() throws {
        let json = #"[{"name":"x","destination":"10.20.60.0/24","target":"1.1.1.1"},{"destination":"10.0.61.0/24","target":"en0","note":"n"}]"#
        let r = try JSONDecoder().decode([SavedRoute].self, from: Data(json.utf8))
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].note, ""); XCTAssertEqual(r[1].name, "")
        XCTAssertEqual(r[1].note, "n")
    }
}

final class ConservativeTests: XCTestCase {
    let netstat = """
    Destination Gateway Flags Netif Expire
    default 192.168.1.1 UGScg en0
    192.168.1 link#6 UCS en0
    192.168.1.37/32 link#6 UCS en0
    192.168.1.1/32 link#6 UCS en0
    10.20.60/24 192.168.1.254 UGSc en0
    10.0.70/24 link#9 UCS utun9
    """
    let ifconfig = "en0: flags=8863<UP> mtu 1500\n\tinet 192.168.1.37 netmask 0xffffff00 broadcast 192.168.1.255\nutun9: flags=8051<UP> mtu 1280\n\tinet 100.64.0.5 --> 100.64.0.5 netmask 0xffffffff\n"

    func testNormalCase() {
        let es = NetstatParser.parse(netstat)
        let sys = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(ifconfig))
        XCTAssertTrue(sys.reliable)
        for e in es.filter({ ["192.168.1.0/24", "192.168.1.37/32", "192.168.1.1/32"].contains($0.destination) }) {
            XCTAssertFalse(sys.isDeletable(e), e.destination)
        }
        // 不可誤殺：經閘道的一般靜態路由、經介面但不含本機位址的路由仍可刪
        XCTAssertTrue(sys.isDeletable(es.first { $0.destination == "10.20.60.0/24" }!))
        XCTAssertTrue(sys.isDeletable(es.first { $0.destination == "10.0.70.0/24" }!))
    }

    func testEmptyIfconfigBlocksEverything() {
        let es = NetstatParser.parse(netstat)
        let sys = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(""))
        XCTAssertFalse(sys.reliable)
        XCTAssertTrue(es.allSatisfy { !sys.isDeletable($0) })
        // 有介面但沒有任何 inet → 同樣不可信
        let noInet = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse("en0: flags=8863<UP> mtu 1500\n"))
        XCTAssertFalse(noInet.reliable)
        XCTAssertFalse(SystemRouteSet.empty.reliable)
        // 來源指令失敗（sourcesOK = false）、netstat 空
        XCTAssertFalse(SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(ifconfig), sourcesOK: false).reliable)
        XCTAssertFalse(SystemRouteSet(entries: [], interfaces: IfconfigParser.parse(ifconfig)).reliable)
        // 已存路由：unreliable 時狀態不會被當成可移除由 UI 層擋；SystemRouteSet 本身對所有列回 false
        XCTAssertFalse(sys.isDeletable(es.first { $0.destination == "10.20.60.0/24" }!))
    }

    func testMissingNetmaskStillSystem() {
        let noMask = "en0: flags=8863<UP> mtu 1500\n\tinet 192.168.1.37 broadcast 192.168.1.255\n"
        let es = NetstatParser.parse(netstat)
        let ifs = IfconfigParser.parse(noMask)
        XCTAssertNil(ifs[0].addresses[0].prefix)
        let sys = SystemRouteSet(entries: es, interfaces: ifs)
        XCTAssertTrue(sys.reliable)
        let lan = es.first { $0.destination == "192.168.1.0/24" }!
        XCTAssertFalse(sys.contains("192.168.1.0/24"))       // 第一道規則抓不到
        XCTAssertTrue(sys.isLinkOwn(lan))                     // 第二道規則抓到
        XCTAssertFalse(sys.isDeletable(lan))
        XCTAssertTrue(sys.isDeletable(es.first { $0.destination == "10.20.60.0/24" }!))
        let saved = SavedRoute(name: "x", destination: "192.168.1.0/24", target: "en0")
        XCTAssertEqual(RouteMatcher.status(of: saved, in: es, system: sys), .system)
    }

    func testHostCommandsAndInterfaceDelete() throws {
        let ifs: Set<String> = ["en0", "utun9"]
        XCTAssertEqual(try RouteCommandBuilder.addCommand(destination: "10.1.2.3/32", target: "1.1.1.1", knownInterfaces: ifs),
                       "/sbin/route -n add -host 10.1.2.3 1.1.1.1")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.1.2.3/32", gateway: "1.1.1.1"),
                       "/sbin/route -n delete -host 10.1.2.3 1.1.1.1")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24", interface: "utun9", knownInterfaces: ifs),
                       "/sbin/route -n delete -net 10.20.60.0/24 -interface utun9")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(destination: "10.1.2.3/32", interface: "en0", knownInterfaces: ifs),
                       "/sbin/route -n delete -host 10.1.2.3 -interface en0")
        XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24", interface: "utun7", knownInterfaces: ifs)) // 不存在
        XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24", interface: "en0; id", knownInterfaces: ifs.union(["en0; id"])))
        XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: "10.20.60.0/24", gateway: "1.1.1.1", interface: "en0", knownInterfaces: ifs))
        XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(destination: "127.0.0.0/8", interface: "lo0", knownInterfaces: ["lo0"]))
    }

    func testRemovalAmbiguity() {
        let es = NetstatParser.parse("Destination Gateway Flags Netif\n10.20.60/24 link#9 UCS utun9\n10.20.60/24 link#4 UCS en0\n10.0.61/24 link#9 UCS utun9\n10.0.62/24 1.1.1.1 UGSc en0\n10.0.63/24 link#4 UCS en0\n10.0.63/24 link#4 UCS en0\n")
        let U = RouteMatcher.removalIsUnambiguous
        XCTAssertTrue(U("10.20.60.0/24", "utun9", es))     // 兩條，但只有一條 utun9
        XCTAssertTrue(U("10.0.61.0/24", "utun9", es))     // 只有一條
        XCTAssertFalse(U("10.0.61.0/24", "en0", es))      // 唯一一條不是這個介面
        XCTAssertFalse(U("10.0.99.0/24", "en0", es))      // 不存在
        XCTAssertFalse(U("10.0.63.0/24", "en0", es))      // 兩條同介面 → 無法分辨
        // 事後核對帶介面：同目的地別的介面還在，不算沒刪掉
        let ex = Expectation(kind: .removed, destination: "10.20.60.0/24", netif: "utun9")
        XCTAssertEqual(RouteVerifier.unmet([ex], in: es), [ex])
        let after = NetstatParser.parse("Destination Gateway Flags Netif\n10.20.60/24 link#4 UCS en0\n")
        XCTAssertEqual(RouteVerifier.unmet([ex], in: after), [])
    }

    func testMissingIdPersisted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("routes.json")
        try #"[{"name":"x","destination":"10.20.60.0/24","target":"1.1.1.1"}]"#.write(to: url, atomically: true, encoding: .utf8)
        let store = RouteStore(url: url)
        let a = try store.load(), b = try store.load()
        XCTAssertEqual(a[0].id, b[0].id)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(a[0].id.uuidString))
    }
}

final class FinalTests: XCTestCase {
    let ifs: Set<String> = ["en0", "utun9"]
    let ifconfig = "en0: flags=8863<UP> mtu 1500\n\tinet 192.168.1.37 netmask 0xffffff00\nutun9: flags=8051<UP> mtu 1280\n\tinet 100.64.0.5 --> 100.64.0.5 netmask 0xffffffff\n"
    let head = "Destination Gateway Flags Netif\ndefault 192.168.1.1 UGScg en0\n"

    func testScopedBlocksBoth() throws {
        let es = NetstatParser.parse(head + "10.9/16 link#17 UCS en0\n10.9/16 link#40 UCSI utun9\n")
        let sys = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(ifconfig))
        XCTAssertTrue(sys.reliable)
        let plain = es.first { $0.destination == "10.9.0.0/16" && $0.netif == "en0" }!
        let scoped = es.first { $0.netif == "utun9" }!
        XCTAssertFalse(sys.isDeletable(scoped))                       // 旗標含 I
        XCTAssertFalse(RouteMatcher.canDeleteEntry(plain, in: es, system: sys))   // 同目的地有 scoped
        XCTAssertFalse(RouteMatcher.canDeleteEntry(scoped, in: es, system: sys))
        for i in ["en0", "utun9"] {
            XCTAssertFalse(RouteMatcher.removalIsUnambiguous(destination: "10.9.0.0/16", interface: i, in: es), i)
        }
        XCTAssertTrue(RouteMatcher.hasScopedRoute(destination: "10.9.0.0/16", in: es))
    }

    func testOnlyEn0DeletableWithInterfaceFlag() throws {
        let es = NetstatParser.parse(head + "10.9/16 link#17 UCS en0\n")
        let sys = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(ifconfig))
        let e = es.first { $0.destination == "10.9.0.0/16" }!
        XCTAssertTrue(RouteMatcher.canDeleteEntry(e, in: es, system: sys))
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(for: e, knownInterfaces: ifs),
                       "/sbin/route -n delete -net 10.9.0.0/16 -interface en0")
        XCTAssertTrue(RouteMatcher.removalIsUnambiguous(destination: "10.9.0.0/16", interface: "en0", in: es))
        // 閘道為 IP 的列：帶閘道，不帶介面
        let g = RouteEntry(destination: "10.8.0.0/16", gateway: "1.2.3.4", flags: "UGSc", netif: "en0")
        XCTAssertEqual(try RouteCommandBuilder.deleteCommand(for: g, knownInterfaces: ifs), "/sbin/route -n delete -net 10.8.0.0/16 1.2.3.4")
        // 介面不存在 → 拒絕
        XCTAssertThrowsError(try RouteCommandBuilder.deleteCommand(for: e, knownInterfaces: ["utun9"]))
    }

    func testLoopbackOnlyIsUnreliable() throws {
        let es = NetstatParser.parse(head + "10.20.60/24 192.168.1.254 UGSc en0\n")
        let loOnly = "lo0: flags=8049<UP,LOOPBACK> mtu 16384\n\tinet 127.0.0.1 netmask 0xff000000\ngif0: flags=8010<POINTOPOINT> mtu 1280\n"
        let sys = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(loOnly))
        XCTAssertFalse(sys.reliable)
        XCTAssertEqual(es.filter { sys.isDeletable($0) }.count, 0)
        // 真實 ifconfig fixture 只留前 8 行（只有 lo0 帶 inet）
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let full = try String(contentsOf: dir.appendingPathComponent("ifconfig-local.txt"), encoding: .utf8)
        let first8 = full.split(separator: "\n", omittingEmptySubsequences: false).prefix(8).joined(separator: "\n")
        let sys8 = SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(first8))
        XCTAssertFalse(sys8.reliable)
        XCTAssertEqual(es.filter { sys8.isDeletable($0) }.count, 0)
        // 加上非 loopback 介面就可信
        XCTAssertTrue(SystemRouteSet(entries: es, interfaces: IfconfigParser.parse(ifconfig)).reliable)
    }

    func testReadOnlyRewriteFailureDoesNotThrow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("routes.json")
        try #"[{"name":"x","destination":"10.20.60.0/24","target":"1.1.1.1"}]"#.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let store = RouteStore(url: url)
        let r = try store.load()                      // 不得丟錯
        XCTAssertEqual(r.count, 1); XCTAssertEqual(r[0].name, "x")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))   // 原檔還在，沒被當壞檔
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["routes.json"])
    }
}
