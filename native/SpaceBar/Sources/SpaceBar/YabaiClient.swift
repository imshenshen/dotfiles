import Foundation
import Darwin

let notificationName = Notification.Name("local.spacebar.yabai.changed")
let eventNames = ["space_changed", "space_created", "space_destroyed", "display_changed", "display_added", "display_removed", "display_moved", "display_resized", "dock_did_restart"]

struct YabaiClient {
    let executable: String
    static func locate() -> String {
        let override = UserDefaults.standard.string(forKey: "yabaiPath")
        return [override, "/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/yabai"
    }
    func command(_ arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .utility) { try Self.run(executable, arguments: ["-m"] + arguments) }.value
    }
    static func run(_ path: String, arguments: [String], timeout: Double = 3) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw BarError(message: detail.isEmpty ? "yabai 命令失败或超时。" : detail)
        }
        return data
    }
    func spaces() async throws -> [Space] {
        try JSONDecoder().decode([Space].self, from: await command(["query", "--spaces"]))
    }
    func snapshot() async throws -> Snapshot {
        let spaces = try await spaces()
        let displays = try JSONDecoder().decode([Display].self, from: await command(["query", "--displays"]))
        return Snapshot(spaces: spaces, displays: displays)
    }
    // Resolve the live index immediately before acting: indices change after display/Space moves.
    func act(id: Int, name: String? = nil) async throws {
        let current = try await spaces()
        guard let space = current.first(where: { $0.id == id }) else { throw BarError(message: "这个 Space 已不存在，请刷新后重试。") }
        if let name {
            let label = try validatedName(name, id: id, spaces: current)
            _ = try await command(["space", String(space.index), "--label", label])
        } else {
            _ = try await command(["space", "--focus", String(space.index)])
        }
    }
    func installSignals(helper: String) async throws {
        let data = try await command(["signal", "--list"])
        let existing = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        let action = "\(shellQuote(helper)) --notify"
        for event in eventNames {
            let label = "local.spacebar.\(event)"
            if existing.contains(where: { $0["label"] as? String == label && $0["action"] as? String == action }) { continue }
            _ = try? await command(["signal", "--remove", label])
            _ = try await command(["signal", "--add", "event=\(event)", "label=\(label)", "action=\(action)"])
        }
    }
    func removeSignals() async {
        for event in eventNames { _ = try? await command(["signal", "--remove", "local.spacebar.\(event)"]) }
    }
}
