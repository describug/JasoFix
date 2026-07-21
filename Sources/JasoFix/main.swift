import SwiftUI

// launchd가 주기 실행할 때 쓰는 헤드리스 모드. UI 없이 변환만 하고 종료한다.
if CommandLine.arguments.contains("--background-run") {
    let folders = UserDefaults.standard.stringArray(forKey: "folders") ?? []
    if !folders.isEmpty {
        let result = NormalizeEngine.run(on: folders)
        if result.updatedRoots != folders {
            UserDefaults.standard.set(result.updatedRoots, forKey: "folders")
        }
        if result.renamed > 0 || result.failed > 0 {
            Log.write("자동 실행: 변환 \(result.renamed)건, 실패 \(result.failed)건")
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
