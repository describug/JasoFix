import Foundation

/// launchd LaunchAgent 등록/해제 관리.
///
/// 백그라운드 자동 실행이 켜져 있으면 ~/Library/LaunchAgents에 plist를 써서
/// 설정된 주기마다 `JasoFix --background-run`이 실행되도록 등록한다.
enum AgentManager {
    static let label = "com.seojungho.jasofix"

    static var plistPath: String {
        NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath
    }

    static func apply() {
        let settings = Settings.shared
        bootout()

        guard settings.backgroundEnabled else {
            try? FileManager.default.removeItem(atPath: plistPath)
            return
        }
        guard let executable = Bundle.main.executablePath else { return }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--background-run"],
            "StartInterval": settings.intervalMinutes * 60,
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        ) else { return }

        try? FileManager.default.createDirectory(
            atPath: (plistPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? data.write(to: URL(fileURLWithPath: plistPath))
        launchctl(["bootstrap", "gui/\(getuid())", plistPath])
    }

    static func bootout() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
