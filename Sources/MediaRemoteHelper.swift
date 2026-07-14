import Cocoa

final class MediaRemoteHelper: ObservableObject {
    static let shared = MediaRemoteHelper()

    @Published var isPlaying = false
    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: NSImage?

    var hasMusic: Bool { isPlaying || !title.isEmpty }

    private var timer: Timer?
    private var lastArtKey = ""
    private var helperProcess: Process?
    private var helperOut: FileHandle?
    private var helperIn: FileHandle?
    private var outputBuffer = Data()
    private var bufferLock = NSLock()

    private init() {}

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipHistoryArt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.queryAndProcess()
        }
        startHelper()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        stopHelper()
    }

    // MARK: - Persistent helper

    private let helperScript = """
    import Foundation
    let bundle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)!
    typealias F = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    let getInfo = unsafeBitCast(dlsym(bundle, "MRMediaRemoteGetNowPlayingInfo")!, to: F.self)
    FileHandle.standardError.write("READY\\n".data(using: .utf8)!)
    while let _ = readLine(strippingNewline: true) {
        let sem = DispatchSemaphore(value: 0)
        var result = "{}"
        getInfo(DispatchQueue.global()) { info in
            var r: [String: Any] = [:]
            if let t = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String { r["title"] = t }
            if let a = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String { r["artist"] = a }
            if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double { r["rate"] = rate }
            if let dur = info["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval { r["duration"] = dur }
            if let pos = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval { r["position"] = pos }
            if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? NSData {
                r["artworkB64"] = Data(bytes: art.bytes, count: art.length).base64EncodedString()
            }
            if let data = try? JSONSerialization.data(withJSONObject: r),
               let s = String(data: data, encoding: .utf8) {
                result = s
            }
            sem.signal()
        }
        sem.wait()
        FileHandle.standardOutput.write((result + "\\n").data(using: .utf8)!)
    }
    """

    private func startHelper() {
        guard helperProcess == nil else { return }
        helperProcess?.terminate()

        let tmpScript = FileManager.default.temporaryDirectory.appendingPathComponent("mr_helper.swift")
        try? helperScript.write(to: tmpScript, atomically: true, encoding: .utf8)

        let proc = Process()
        let outPipe = Pipe()
        let inPipe = Pipe()
        let errPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        proc.arguments = [tmpScript.path]
        proc.standardOutput = outPipe
        proc.standardInput = inPipe
        proc.standardError = errPipe

        do {
            try proc.run()
            helperProcess = proc
            helperOut = inPipe.fileHandleForWriting
            helperIn = outPipe.fileHandleForReading

            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let s = String(data: data, encoding: .utf8), s.contains("READY") {
                    self?.queryAndProcess()
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.bufferLock.lock()
                self?.outputBuffer.append(data)
                self?.bufferLock.unlock()
            }
        } catch {
            helperProcess = nil
        }
    }

    private func stopHelper() {
        helperProcess?.terminate()
        helperProcess = nil
        helperOut = nil
        helperIn = nil
    }

    private func queryAndProcess() {
        guard let input = helperOut else { return }
        let cmd = "\n".data(using: .utf8)!
        input.write(cmd)

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.bufferLock.lock()
            let data = self?.outputBuffer ?? Data()
            self?.outputBuffer = Data()
            self?.bufferLock.unlock()

            guard !data.isEmpty,
                  let str = String(data: data, encoding: .utf8),
                  let lastLine = str.components(separatedBy: "\n").last(where: { !$0.isEmpty }),
                  let jsonData = lastLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return
            }
            self?.processResult(json)
        }
    }

    private func processResult(_ json: [String: Any]) {
        let newTitle = json["title"] as? String ?? ""
        let newArtist = json["artist"] as? String ?? ""
        let playing = (json["rate"] as? Double ?? 0) > 0
        let artB64 = json["artworkB64"] as? String

        let artKey = "\(newTitle)|\(newArtist)"
        let trackChanged = (artKey != lastArtKey)
        if trackChanged { lastArtKey = artKey }

        var newArtwork: NSImage?

        if playing && trackChanged {
            newArtwork = loadFromCache(key: artKey)
            if newArtwork == nil, let b64 = artB64,
               let data = Data(base64Encoded: b64),
               let img = NSImage(data: data) {
                newArtwork = img
                saveToCache(key: artKey, data: data)
            }
        } else if playing {
            newArtwork = self.artwork
        }

        DispatchQueue.main.async {
            let changed = self.title != newTitle || self.artist != newArtist || self.isPlaying != playing
            self.isPlaying = playing
            self.title = newTitle
            self.artist = newArtist
            if let art = newArtwork { self.artwork = art }
            if changed {
                NotificationCenter.default.post(name: .musicStateChanged, object: nil)
            }
        }
    }

    // MARK: - Commands

    func togglePlayPause() { sendOsascript("tell application \"Spotify\" to playpause") }
    func previousTrack() { sendOsascript("tell application \"Spotify\" to previous track") }
    func nextTrack() { sendOsascript("tell application \"Spotify\" to next track") }

    private func sendOsascript(_ cmd: String) {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", cmd]
            try? task.run()
        }
    }

    // MARK: - Cache

    private func cacheKey(for key: String) -> URL {
        let hash = key.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? "x"
        return cacheDir.appendingPathComponent(String(hash.prefix(32)) + ".jpg")
    }

    private func loadFromCache(key: String) -> NSImage? {
        guard let data = try? Data(contentsOf: cacheKey(for: key)) else { return nil }
        return NSImage(data: data)
    }

    private func saveToCache(key: String, data: Data) {
        try? data.write(to: cacheKey(for: key))
    }
}

extension Notification.Name {
    static let musicStateChanged = Notification.Name("musicStateChanged")
}
