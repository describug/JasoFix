import SwiftUI

// launchd가 주기 실행할 때 쓰는 헤드리스 모드. UI 없이 변환만 하고 종료한다.
if CommandLine.arguments.contains("--background-run") {
    let folders = UserDefaults.standard.stringArray(forKey: "folders") ?? []
    if !folders.isEmpty {
        let result = NormalizeEngine.run(on: folders)
        if result.updatedRoots != folders {
            UserDefaults.standard.set(result.updatedRoots, forKey: "folders")
        }
        if result.renamed > 0 || result.failed > 0 || !result.unreadable.isEmpty {
            Log.write("자동 실행: \(result.summary)" + Log.unreadableDetail(result.unreadable))
        }
        // 화면이 없으니 문제는 남겨 두었다가 다음에 설정 창을 열 때 보여준다
        if result.failed > 0 || !result.unreadable.isEmpty {
            UserDefaults.standard.set(
                "\(Log.timestamp()) 자동 실행 — \(result.summary)" + Log.unreadableDetail(result.unreadable),
                forKey: "lastBackgroundIssue"
            )
        }
    }
    exit(0)
}

struct JasoFixApp: App {
    init() {
        // 앱 위치가 바뀌었을 수 있으므로 실행할 때마다 LaunchAgent 경로를 갱신한다.
        if Settings.shared.backgroundEnabled {
            AgentManager.apply()
        }
    }

    var body: some Scene {
        WindowGroup("JasoFix") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

JasoFixApp.main()
