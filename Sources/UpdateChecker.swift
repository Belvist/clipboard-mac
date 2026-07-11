import Cocoa

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var downloadURL = ""
    @Published var isDownloading = false
    @Published var isChecking = false
    @Published var downloadProgress: Double = 0
    @Published var updateError: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    private var backupPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ClipHistory_backup.app")
    }

    private static let baseURL = "https://api.github.com/repos/Belvist/clipboard-mac"

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

    // MARK: - Check

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        updateError = nil
        guard let url = URL(string: "\(Self.baseURL)/releases/latest") else {
            DispatchQueue.main.async { self.isChecking = false }
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                DispatchQueue.main.async {
                    self.isChecking = false
                    self.updateError = "network_error"
                }
                return
            }
            DispatchQueue.main.async {
                self.latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                self.hasUpdate = Self.isNewer(latest: self.latestVersion, current: self.currentVersion)
                if let assets = json["assets"] as? [[String: Any]],
                   let asset = assets.first,
                   let browserURL = asset["browser_download_url"] as? String {
                    self.downloadURL = browserURL
                }
                self.isChecking = false
            }
        }.resume()
    }

    // MARK: - Download & Update

    func downloadAndUpdate() {
        guard let url = URL(string: downloadURL) else {
            updateError = "invalid_url"
            return
        }
        isDownloading = true
        downloadProgress = 0
        updateError = nil

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            let cleanup = { (err: String?) in
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.updateError = err
                }
            }

            guard let data = data, error == nil else {
                cleanup("download_failed"); return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                cleanup("download_failed"); return
            }
            guard data.count > 1000 else {
                cleanup("corrupt_download"); return
            }
            guard data.starts(with: [0x50, 0x4B]) else {
                cleanup("corrupt_download"); return
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

                guard unzip.terminationStatus == 0 else {
                    cleanup("unzip_failed"); return
                }

                guard let appPath = self.findAppInDirectory(tempDir) else {
                    cleanup("invalid_bundle"); return
                }

                let binaryPath = appPath.appendingPathComponent("Contents/MacOS/ClipHistory")
                let infoPath = appPath.appendingPathComponent("Contents/Info.plist")

                guard FileManager.default.fileExists(atPath: binaryPath.path),
                      FileManager.default.fileExists(atPath: infoPath.path) else {
                    cleanup("invalid_bundle"); return
                }

                guard self.isExecutable(binaryPath) else {
                    cleanup("invalid_bundle"); return
                }

                let newVersion = NSDictionary(contentsOf: infoPath)?["CFBundleShortVersionString"] as? String ?? ""
                guard !newVersion.isEmpty, Self.isNewer(latest: newVersion, current: self.currentVersion) else {
                    cleanup("version_not_newer"); return
                }

                try? FileManager.default.removeItem(at: self.backupPath)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: Bundle.main.bundlePath), to: self.backupPath)

                let currentAppPath = Bundle.main.bundlePath
                let myPID = ProcessInfo.processInfo.processIdentifier
                let backupPath = self.backupPath.path

                let script = """
                #!/bin/bash
                for i in $(seq 1 50); do
                    if ! kill -0 \(myPID) 2>/dev/null; then break; fi
                    sleep 0.1
                done
                sleep 0.5

                DEST="\(currentAppPath)"
                NEW="\(appPath.path)"
                BACKUP="\(backupPath)"
                TRASH="$HOME/.Trash/ClipHistory_old_\(stamp).app"

                rm -rf "$TRASH" 2>/dev/null
                mv "$DEST" "$TRASH" 2>/dev/null
                mv "$NEW" "$DEST" 2>/dev/null

                if [ ! -f "$DEST/Contents/MacOS/ClipHistory" ]; then
                    rm -rf "$DEST" 2>/dev/null
                    mv "$BACKUP" "$DEST" 2>/dev/null
                else
                    rm -rf "$BACKUP" 2>/dev/null
                fi

                rm -rf "\(tempDir.path)" 2>/dev/null
                open "$DEST" 2>/dev/null
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
                self.cleanupTempDir(tempDir)
                cleanup("update_failed")
            }
        }
        task.resume()
    }

    // MARK: - Helpers

    private func findAppInDirectory(_ dir: URL) -> URL? {
        let directApp = dir.appendingPathComponent("ClipHistory.app")
        if FileManager.default.fileExists(atPath: directApp.path),
           FileManager.default.fileExists(atPath: directApp.appendingPathComponent("Contents/MacOS/ClipHistory").path) {
            return directApp
        }

        let contentsDir = dir.appendingPathComponent("Contents")
        if FileManager.default.fileExists(atPath: contentsDir.path),
           FileManager.default.fileExists(atPath: contentsDir.appendingPathComponent("MacOS/ClipHistory").path) {
            let appDir = dir.appendingPathComponent("ClipHistory.app")
            let appContents = appDir.appendingPathComponent("Contents")
            try? FileManager.default.createDirectory(at: appContents, withIntermediateDirectories: true)
            for item in (try? FileManager.default.contentsOfDirectory(at: contentsDir, includingPropertiesForKeys: nil)) ?? [] {
                let dest = appContents.appendingPathComponent(item.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: item, to: dest)
            }
            try? FileManager.default.removeItem(at: contentsDir)
            return FileManager.default.fileExists(atPath: appDir.path) ? appDir : nil
        }

        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "ClipHistory.app" {
                    let macosPath = fileURL.appendingPathComponent("Contents/MacOS/ClipHistory")
                    if FileManager.default.fileExists(atPath: macosPath.path) {
                        return fileURL
                    }
                }
            }
        }

        return nil
    }

    private func isExecutable(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func cleanupTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    func restoreBackupIfNeeded() {
        guard FileManager.default.fileExists(atPath: backupPath.path) else { return }
        let currentBinary = Bundle.main.bundlePath + "/Contents/MacOS/ClipHistory"
        if FileManager.default.fileExists(atPath: currentBinary) {
            try? FileManager.default.removeItem(at: backupPath)
            return
        }
        try? FileManager.default.copyItem(at: backupPath, to: URL(fileURLWithPath: Bundle.main.bundlePath))
        try? FileManager.default.removeItem(at: backupPath)
    }
}
