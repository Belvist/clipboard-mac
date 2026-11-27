import Cocoa

// MARK: - Debug Logging

#if DEBUG
private let logQueue = DispatchQueue(label: "com.cliphistory.log", qos: .utility)

func debugLog(_ msg: String) {
    let line = "[ClipHistory] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    logQueue.async {
        let path = "/tmp/cliphistory_debug.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
#else
func debugLog(_ msg: String) {}
#endif

// MARK: - MediaRemote (in-process, no subprocess)

final class MediaRemoteHelper: ObservableObject {
    static let shared = MediaRemoteHelper()

    @Published var isPlaying = false
    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: NSImage?
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    var hasMusic: Bool { isPlaying || !title.isEmpty }

    private var timer: Timer?
    private var elapsedTimer: Timer?
    private var lastArtKey = ""
    private var lastSync = Date.distantPast
    private var idlePolls = 0
    private var hasPostedInitialState = false
    private var localElapsedBase: TimeInterval = 0
    private var localElapsedSince = Date()

    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, NSDictionary?) -> Bool

    private lazy var mediaRemoteBundle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    }()

    private lazy var getNowPlayingInfo: GetNowPlayingInfoFn? = {
        guard let bundle = mediaRemoteBundle,
              let sym = dlsym(bundle, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
        return unsafeBitCast(sym, to: GetNowPlayingInfoFn.self)
    }()

    private lazy var sendCommand: SendCommandFn? = {
        guard let bundle = mediaRemoteBundle,
              let sym = dlsym(bundle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendCommandFn.self)
    }()

    private init() {}

    func startPolling() {
        timer?.invalidate()
        scheduleNextPoll(interval: 2.0)
        queryNowPlaying()

        // Lightweight 1 Hz ticker so the elapsed clock advances smoothly
        // without spawning any subprocess. Only updates `elapsed`.
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickElapsed()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func scheduleNextPoll(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.queryNowPlaying()
        }
    }

    private func nextPollInterval(playing: Bool) -> TimeInterval {
        if playing { return 1.0 }
        idlePolls += 1
        if idlePolls > 15 { return 8.0 }
        if idlePolls > 5 { return 4.0 }
        return 2.0
    }

    private func queryNowPlaying() {
        guard let getInfo = getNowPlayingInfo else {
            scheduleNextPoll(interval: 5.0)
            return
        }

        getInfo(DispatchQueue.global(qos: .utility)) { [weak self] info in
            self?.processResult(info)
        }
    }

    private func processResult(_ info: [String: Any]) {
        let newTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let newArtist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let playing = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0) > 0
        let newDuration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? 0
        let jsonPosition = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval

        let artKey = "\(newTitle)|\(newArtist)"
        let trackChanged = artKey != lastArtKey
        if trackChanged { lastArtKey = artKey }

        var newArtwork: NSImage?
        if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
           let img = NSImage(data: art) {
            newArtwork = img
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let changed = self.title != newTitle || self.artist != newArtist || self.isPlaying != playing

            if trackChanged {
                self.localElapsedBase = jsonPosition ?? 0
                self.localElapsedSince = Date()
                self.elapsed = self.localElapsedBase
            } else if playing {
                if let pos = jsonPosition, pos.isFinite, Date().timeIntervalSince(self.lastSync) > 8 {
                    self.localElapsedBase = pos
                    self.localElapsedSince = Date()
                    self.elapsed = pos
                    self.lastSync = Date()
                } else {
                    self.elapsed = self.localElapsedBase + Date().timeIntervalSince(self.localElapsedSince)
                }
            }

            self.isPlaying = playing
            self.title = newTitle
            self.artist = newArtist
            if newDuration > 0 { self.duration = newDuration }
            if let art = newArtwork {
                self.artwork = art
            } else if trackChanged && !playing {
                self.artwork = nil
            }

            if playing {
                self.idlePolls = 0
            }

            if changed || !self.hasPostedInitialState {
                self.hasPostedInitialState = true
                debugLog("music: playing=\(playing) \(newTitle)")
                NotificationCenter.default.post(name: .musicStateChanged, object: nil)
            }

            self.scheduleNextPoll(interval: self.nextPollInterval(playing: playing))
        }
    }

    func tickElapsed() {
        guard isPlaying else { return }
        elapsed = localElapsedBase + Date().timeIntervalSince(localElapsedSince)
    }

    // MARK: - Commands

    func togglePlayPause() { sendMRCommand(2) }
    func previousTrack() { sendMRCommand(5) }
    func nextTrack() { sendMRCommand(4) }

    func seekTo(_ position: TimeInterval) {
        let pos = max(0, min(position, duration > 0 ? duration : .greatestFiniteMagnitude))
        localElapsedBase = pos
        localElapsedSince = Date()
        elapsed = pos
        sendMRCommand(24, userInfo: ["kMRMediaRemoteOptionPlaybackPosition": pos])
    }

    private func sendMRCommand(_ command: UInt32, userInfo: [String: Any]? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.sendCommand?(command, userInfo as NSDictionary?)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.queryNowPlaying()
            }
        }
    }
}

extension Notification.Name {
    static let musicStateChanged = Notification.Name("musicStateChanged")
}
