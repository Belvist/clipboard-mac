import Cocoa

func checkAccessibility() -> Bool {
    AXIsProcessTrusted()
}

func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "ClipHistory needs Accessibility access to paste text into other apps.\n\nPlease enable it in:\nSystem Settings → Privacy & Security → Accessibility\n\nThen restart ClipHistory."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .warning
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }
    }
}
