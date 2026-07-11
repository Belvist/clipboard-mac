import Cocoa

func checkAccessibility() -> Bool {
    AXIsProcessTrusted()
}

func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
