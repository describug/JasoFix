import Foundation
import AppKit

/// GitHub 릴리스로 새 버전을 확인하고, 받아서 앱을 바꿔 끼운 뒤 다시 실행한다.
///
/// 따로 배포 서버를 두지 않는다. 공개 저장소의 최신 릴리스(tag_name, JasoFix.zip)가
/// 곧 업데이트 정보다. 테스트할 때는 환경변수 JASOFIX_UPDATE_FEED 로 주소를 바꾼다.
enum Updater {
    struct Release {
        let version: String
        let zipURL: URL
    }

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }

    static let releasesPage = URL(string: "https://github.com/describug/JasoFix/releases/latest")!

    private static var feedURL: URL {
        if let override = ProcessInfo.processInfo.environment["JASOFIX_UPDATE_FEED"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.github.com/repos/describug/JasoFix/releases/latest")!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 지금보다 새 버전이 있으면 돌려준다. 네트워크 오류 등은 조용히 nil.
    static func checkForUpdate() async -> Release? {
        var request = URLRequest(url: feedURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == "JasoFix.zip" }),
              let link = asset["browser_download_url"] as? String,
              let zipURL = URL(string: link)
        else { return nil }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: currentVersion) else { return nil }
        return Release(version: version, zipURL: zipURL)
    }

    /// "1.10.0" > "1.9.2" 처럼 점으로 나눈 숫자 단위로 비교한다.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static let workPrefix = "JasoFix-update-"

    /// 지난 업데이트가 남긴 작업 폴더를 지운다. 1.3.0 은 이 폴더를 지우지 않아
    /// 옛 앱(old.app)과 zip 이 회당 약 0.8MB씩 쌓였다. 설정 창을 열 때 부른다.
    static func removeLeftovers() {
        let temp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        for name in names where name.hasPrefix(workPrefix) {
            try? FileManager.default.removeItem(at: temp.appendingPathComponent(name))
        }
    }

    /// 새 버전을 받아 지금 앱 자리에 바꿔 끼운다. 성공하면 재실행 예약 후 앱을 종료한다.
    static func install(_ release: Release) async throws {
        let appURL = Bundle.main.bundleURL
        if appURL.path.contains("/AppTranslocation/") {
            throw UpdateError.message("앱을 응용 프로그램 폴더로 옮긴 뒤 다시 실행해 주세요.")
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent(workPrefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            try await replaceApp(at: appURL, with: release, work: work)
        } catch {
            // 옛 앱을 제자리로 못 돌려놓은 경우엔 작업 폴더(old.app)가 유일한 사본이라 남긴다
            if FileManager.default.fileExists(atPath: appURL.path) {
                try? FileManager.default.removeItem(at: work)
            }
            throw error
        }
        // 옛 앱(old.app)은 지금 실행 중인 파일이라 종료 뒤에 지운다
        relaunch(appURL, removing: work)
    }

    private static func replaceApp(at appURL: URL, with release: Release, work: URL) async throws {
        let (downloaded, response) = try await URLSession.shared.download(from: release.zipURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.message("다운로드 실패 (HTTP \(http.statusCode))")
        }
        let zip = work.appendingPathComponent("JasoFix.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

        // .app 의 심볼릭 링크·실행권한을 지키려고 ditto 로 푼다 (릴리스도 ditto 로 압축)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else {
            throw UpdateError.message("압축을 풀지 못했습니다.")
        }
        let newApp = work.appendingPathComponent("JasoFix.app")
        guard let info = Bundle(url: newApp)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == release.version
        else {
            throw UpdateError.message("받은 파일이 올바른 JasoFix가 아닙니다.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", newApp.path]) == 0 else {
            throw UpdateError.message("받은 앱의 서명이 손상되었습니다.")
        }

        // 실행 중인 앱 번들도 옮길 수 있다 (이미 열린 파일은 그대로 남는다).
        // 옛 앱은 작업 폴더로 빼 두었다가, 새 앱을 못 넣으면 되돌린다.
        let backup = work.appendingPathComponent("old.app")
        do {
            try FileManager.default.moveItem(at: appURL, to: backup)
        } catch {
            throw UpdateError.message("앱을 바꿀 권한이 없습니다. 다운로드 페이지에서 직접 받아 주세요.")
        }
        do {
            try FileManager.default.moveItem(at: newApp, to: appURL)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: appURL)
            throw UpdateError.message("새 앱을 설치하지 못했습니다.")
        }
    }

    /// 이 프로세스가 끝나기를 기다렸다가 작업 폴더를 지우고 새 앱을 여는 셸을 띄운 뒤 종료한다.
    /// (살아 있는 동안 open 하면 같은 앱이라 기존 창만 앞으로 온다)
    private static func relaunch(_ appURL: URL, removing work: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; rm -rf \"$1\"; open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, appURL.path, work.path]
        try? process.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
