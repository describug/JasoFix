import Foundation

/// 한글 파일명 자소 분리(NFD) → 조합형(NFC) 변환 엔진.
///
/// 맥(APFS)은 한글 파일명을 자소 분리형(NFD)으로 저장하는 경우가 많아,
/// 윈도우(원격 데스크톱, 클라우드 동기화 등)에서 파일명이 "ㅇㅓㅂㅁㅜ"처럼
/// 조각나 보인다. 이 엔진은 폴더 트리를 순회하며 NFD 이름을 NFC로 rename한다.
enum NormalizeEngine {

    struct Result {
        var renamed = 0
        var failed = 0
        /// 권한 등으로 열지 못해 건너뛴 폴더. 그 안의 파일은 변환되지 않았다.
        var unreadable: [String] = []
        /// 대상 폴더 자체가 rename된 경우를 반영한 새 경로 목록 (설정 갱신용)
        var updatedRoots: [String] = []

        /// "변환 3건, 실패 1건, 읽지 못한 폴더 2개" 형태의 요약
        var summary: String {
            var text = "변환 \(renamed)건, 실패 \(failed)건"
            if !unreadable.isEmpty { text += ", 읽지 못한 폴더 \(unreadable.count)개" }
            return text
        }
    }

    /// Swift의 String ==는 유니코드 정준 동등성 비교라 NFD == NFC가 true가 된다.
    /// 반드시 UTF-8 바이트로 비교해야 실제 저장 형태의 차이를 감지할 수 있다.
    static func needsNormalize(_ name: String) -> Bool {
        Array(name.utf8) != Array(name.precomposedStringWithCanonicalMapping.utf8)
    }

    static func run(on roots: [String]) -> Result {
        var result = Result()
        for root in roots {
            runSingle(root: root, result: &result)
            result.updatedRoots.append(normalizeRoot(root, result: &result))
        }
        return result
    }

    /// 대상 폴더 자체의 이름도 NFC로 바꾸고, 바뀐 경우 새 경로를 돌려준다.
    private static func normalizeRoot(_ root: String, result: inout Result) -> String {
        let parent = (root as NSString).deletingLastPathComponent
        let want = (root as NSString).lastPathComponent
        guard !parent.isEmpty, parent != root else { return root }

        // 설정에 저장된 경로와 디스크의 실제 저장 형태(NFD/NFC)가 다를 수 있으므로
        // 부모 폴더 목록에서 실제 항목을 찾는다. Swift String ==는 정준 동등 비교라
        // 형태가 달라도 매칭된다.
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
        guard let actual = entries.first(where: { $0 == want }) else { return root }
        guard needsNormalize(actual) else { return parent + "/" + actual }

        let source = parent + "/" + actual
        let dest = parent + "/" + actual.precomposedStringWithCanonicalMapping
        let ok = source.withCString { src in
            dest.withCString { dst in
                rename(src, dst) == 0
            }
        }
        if ok {
            result.renamed += 1
            return dest
        }
        result.failed += 1
        return root
    }

    /// 폴더를 실제로 열어 본다. 권한(TCC 포함)이 없으면 열리지 않는다.
    /// FileManager 의 열거자는 못 여는 폴더를 오류 없이 건너뛰므로 직접 확인해야 한다.
    private static func canOpen(_ path: String) -> Bool {
        guard let dir = opendir(path) else { return false }
        closedir(dir)
        return true
    }

    private static func runSingle(root: String, result: inout Result) {
        let fm = FileManager.default
        guard canOpen(root), let enumerator = fm.enumerator(atPath: root) else {
            result.unreadable.append(root)
            return
        }

        var relPaths: [String] = []
        while let rel = enumerator.nextObject() as? String {
            relPaths.append(rel)
            if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory,
               !canOpen(root + "/" + rel) {
                result.unreadable.append(root + "/" + rel)
            }
        }
        // 하위 항목부터 처리해야 상위 폴더를 rename해도 경로가 꼬이지 않는다.
        relPaths.sort {
            $0.components(separatedBy: "/").count > $1.components(separatedBy: "/").count
        }

        for rel in relPaths {
            let name = (rel as NSString).lastPathComponent
            guard needsNormalize(name) else { continue }

            let full = root + "/" + rel
            let dest = (full as NSString).deletingLastPathComponent + "/"
                + name.precomposedStringWithCanonicalMapping

            // FileManager.fileSystemRepresentation은 경로를 다시 NFD로 바꿔버리므로
            // 문자열의 UTF-8 바이트를 그대로 쓰는 POSIX rename을 사용한다.
            let ok = full.withCString { src in
                dest.withCString { dst in
                    rename(src, dst) == 0
                }
            }
            if ok { result.renamed += 1 } else { result.failed += 1 }
        }
    }
}

enum Log {
    static let path = NSString(string: "~/Library/Logs/JasoFix.log").expandingTildeInPath

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    /// 읽지 못한 폴더 목록을 로그·안내용으로 덧붙인다 (많으면 앞의 3개만)
    static func unreadableDetail(_ folders: [String]) -> String {
        guard !folders.isEmpty else { return "" }
        var text = "\n  읽지 못한 폴더: " + folders.prefix(3).joined(separator: ", ")
        if folders.count > 3 { text += " 외 \(folders.count - 3)개" }
        return text
    }

    static func write(_ message: String) {
        let line = "\(timestamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
