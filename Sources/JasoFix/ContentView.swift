import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var selection = Set<String>()
    @State private var running = false
    @State private var lastMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("대상 폴더").font(.headline)
            List(selection: $selection) {
                ForEach(settings.folders, id: \.self) { folder in
                    Text(folder).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(minHeight: 140)
            .border(Color.gray.opacity(0.2))

            HStack {
                Button("폴더 추가…", action: addFolders)
                Button("선택 삭제", action: removeSelected)
                    .disabled(selection.isEmpty)
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: { run(settings.folders) }) {
                    Text("전체 폴더 실행").frame(minWidth: 110)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(running || settings.folders.isEmpty)

                Button(action: { run(settings.folders.filter { selection.contains($0) }) }) {
                    Text("선택 폴더만 실행").frame(minWidth: 110)
                }
                .disabled(running || selection.isEmpty)

                if running {
                    ProgressView().controlSize(.small)
                    Text("변환 중…").foregroundColor(.secondary)
                } else {
                    Text(lastMessage).foregroundColor(.secondary)
                }
            }

            Divider()

            Toggle("백그라운드 자동 실행", isOn: $settings.backgroundEnabled)
            HStack {
                Text("실행 주기(분):")
                TextField("5", value: $settings.intervalMinutes, format: .number)
                    .frame(width: 56)
                Stepper("", value: $settings.intervalMinutes, in: 1...1440)
                    .labelsHidden()
            }
            .disabled(!settings.backgroundEnabled)

            Text("자동 실행 기록: ~/Library/Logs/JasoFix.log")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("JasoFix \(appVersion) · © 2026 describug · MIT License")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 480)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "추가"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !settings.folders.contains(url.path) {
            settings.folders.append(url.path)
        }
    }

    private func removeSelected() {
        settings.folders.removeAll { selection.contains($0) }
        selection.removeAll()
    }

    private func run(_ folders: [String]) {
        running = true
        let label = folders.count == settings.folders.count ? "전체" : "선택 \(folders.count)개"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = NormalizeEngine.run(on: folders)
            Log.write("수동 실행(\(label)): 변환 \(result.renamed)건, 실패 \(result.failed)건")
            DispatchQueue.main.async {
                // 대상 폴더 자체가 rename됐으면 설정 경로와 선택도 갱신한다.
                // updatedRoots는 입력 folders와 같은 순서다. String !=는 NFD/NFC를
                // 같다고 보므로 바이트로 비교한다.
                let renamed = Dictionary(uniqueKeysWithValues: zip(folders, result.updatedRoots))
                    .filter { Array($0.key.utf8) != Array($0.value.utf8) }
                if !renamed.isEmpty {
                    settings.folders = settings.folders.map { renamed[$0] ?? $0 }
                    selection = Set(selection.map { renamed[$0] ?? $0 })
                }
                running = false
                var message = "완료(\(label)) — 변환 \(result.renamed)건"
                if result.failed > 0 { message += ", 실패 \(result.failed)건" }
                lastMessage = message
            }
        }
    }
}
