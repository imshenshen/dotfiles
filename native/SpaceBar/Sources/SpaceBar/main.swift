import AppKit

if CommandLine.arguments.contains("--notify") {
    DistributedNotificationCenter.default().postNotificationName(notificationName, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
if CommandLine.arguments.contains("--check") {
    Task {
        do {
            let snapshot = try await YabaiClient(executable: YabaiClient.locate()).snapshot()
            print("Connected: \(snapshot.displays.count) displays, \(snapshot.spaces.count) spaces")
            for space in snapshot.spaces { print("\(space.index) [\(space.hint)] \(space.name) visible=\(space.visible) focused=\(space.focused)") }
            exit(0)
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
