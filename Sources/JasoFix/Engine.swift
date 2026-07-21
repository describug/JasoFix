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
        }
        return result
    }

    private static func runSingle(root: String, result: inout Result) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else { return }

        var relPaths: [String] = []
        while let rel = enumerator.nextObject() as? String {
            relPaths.append(rel)
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

    static func write(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) \(message)\n"
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
