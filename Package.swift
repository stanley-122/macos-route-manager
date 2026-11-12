// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RouteManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RouteManager", targets: ["RouteManager"])
    ],
    targets: [
        // 純邏輯：解析、驗證、組指令、儲存。不碰 UI、不碰特權。
        .target(name: "RouteCore"),
        .executableTarget(name: "RouteManager", dependencies: ["RouteCore"]),
        .testTarget(name: "RouteCoreTests", dependencies: ["RouteCore"], exclude: ["Fixtures"]),
    ]
)
