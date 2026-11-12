import Foundation
import AppKit
import RouteCore

struct ShellResult {
    var out: String; var err: String; var status: Int32
    /// 啟動成功且結束碼為 0（空輸出但成功仍為 true，由呼叫端另外判斷內容）
    var ok: Bool { status == 0 }
}

enum Shell {
    /// 執行寫死路徑的指令（不經 shell）。不需權限。
    static func run(_ path: String, _ args: [String]) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        do { try p.run() } catch { return ShellResult(out: "", err: error.localizedDescription, status: -1) }
        // 先讀 stderr 在背景，避免管線塞滿
        var errData = Data()
        let g = DispatchGroup(); g.enter()
        DispatchQueue.global().async { errData = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        let outData = o.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); g.wait()
        return ShellResult(out: String(decoding: outData, as: UTF8.self), err: String(decoding: errData, as: UTF8.self), status: p.terminationStatus)
    }
}

enum PrivilegedResult {
    case output(String)
    case canceled
    case failure(String)
}

enum PrivilegedRunner {
    /// 以系統標準授權視窗執行（osascript do shell script … with administrator privileges）。
    static func run(script: String) -> PrivilegedResult {
        let r = Shell.run("/usr/bin/osascript", ["-e", RouteCommandBuilder.appleScript(for: script)])
        if r.status == 0 { return .output(r.out.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if r.err.contains("-128") || r.err.lowercased().contains("user canceled") { return .canceled }
        return .failure(r.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
