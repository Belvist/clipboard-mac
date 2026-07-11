import Cocoa

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var downloadURL = ""
    @Published var isDownloading = false
    @Published var isChecking = false
    @Published var downloadProgress: Double = 0

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    static func isNewer(latest: String, current: String) -> Bool {
        guard !latest.isEmpty, !current.isEmpty else { return false }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(latestParts.count, currentParts.count)
        for i in 0..<count {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        guard let url = URL(string: "https://api.github.com/repos/Belvist/clipboard-mac/releases/latest") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String else {
                DispatchQueue.main.async { self.isChecking = false }
                return
            }
            DispatchQueue.main.async {
                self.latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                self.hasUpdate = UpdateChecker.isNewer(latest: self.latestVersion, current: self.currentVersion)
                if let assets = json["assets"] as? [[String: Any]],
                   let asset = assets.first,
                   let browserURL = asset["browser_download_url"] as? String {
                    self.downloadURL = browserURL
                }
                self.isChecking = false
            }
        }.resume()
    }

    func downloadAndUpdate() {
        guard let url = URL(string: downloadURL) else { return }
        isDownloading = true
        downloadProgress = 0

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async { self?.isDownloading = false }
                return
            }

            let stamp = Int(Date().timeIntervalSince1970)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipHistory_update_\(stamp)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("ClipHistory.app.zip")

            do {
                try data.write(to: zipPath)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", zipPath.path, "-d", tempDir.path]
                try unzip.run()
                unzip.waitUntilExit()

                let newAppPath = tempDir.appendingPathComponent("ClipHistory.app")
                guard FileManager.default.fileExists(atPath: newAppPath.path) else {
                    DispatchQueue.main.async { self.isDownloading = false }
                    return
                }

                let currentAppPath = Bundle.main.bundlePath
                let myPID = ProcessInfo.processInfo.processIdentifier

                let script = """
                #!/bin/bash
                for i in $(seq 1 50); do
                    if ! kill -0 \(myPID) 2>/dev/null; then break; fi
                    sleep 0.1
                done
                sleep 0.5
                DEST="\(currentAppPath)"
                NEW="\(newAppPath.path)"
                TRASH="$HOME/.Trash/ClipHistory_old_\(stamp).app"
                rm -rf "$TRASH" 2>/dev/null
                mv "$DEST" "$TRASH" 2>/dev/null
                mv "$NEW" "$DEST" 2>/dev/null
                rm -rf "\(tempDir.path)" 2>/dev/null
                open "$DEST"
                """

                let scriptPath = tempDir.appendingPathComponent("relaunch.sh")
                try script.write(toFile: scriptPath.path, atomically: true, encoding: .utf8)

                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", scriptPath.path]
                try chmod.run(); chmod.waitUntilExit()

                let bash = Process()
                bash.executableURL = URL(fileURLWithPath: "/bin/bash")
                bash.arguments = ["-c", "nohup \(scriptPath.path) >/dev/null 2>&1 &"]
                bash.standardOutput = FileHandle.nullDevice
                bash.standardError = FileHandle.nullDevice
                try bash.run()
                bash.waitUntilExit()

                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.hasUpdate = false

                    let alert = NSAlert()
                    alert.messageText = L10n.shared.tr("update_ready")
                    alert.informativeText = String(format: L10n.shared.tr("update_info"), self.latestVersion)
                    alert.addButton(withTitle: L10n.shared.tr("restart"))
                    alert.runModal()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async { self.isDownloading = false }
            }
        }
        task.resume()
    }
}
