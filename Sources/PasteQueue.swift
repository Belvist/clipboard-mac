import Cocoa

class PasteQueue: ObservableObject {
    static let shared = PasteQueue()
    @Published var items: [ClipItem] = []
    @Published var isActive = false
    @Published var currentIndex = 0

    func enqueue(_ items: [ClipItem]) {
        self.items = items
        self.currentIndex = 0
        self.isActive = true
        pasteNext()
    }

    func pasteNext() {
        guard currentIndex < items.count else { stop(); return }
        let item = items[currentIndex]
        NSPasteboard.general.clearContents()

        if let img = item.nsImage {
            NSPasteboard.general.writeObjects([img])
        } else {
            NSPasteboard.general.setString(item.text, forType: .string)
        }
        ClipboardManager.shared.syncLastFromPasteboard()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                keyUp?.flags = .maskCommand
                keyUp?.post(tap: .cghidEventTap)
                self.currentIndex += 1
                if self.currentIndex < self.items.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.pasteNext() }
                } else { self.stop() }
            }
        }
    }

    func stop() {
        isActive = false
        items = []
        currentIndex = 0
    }
}
