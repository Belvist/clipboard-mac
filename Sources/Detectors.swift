import Foundation

struct SensitiveDetector {
    static func detect(_ text: String) -> (isSensitive: Bool, type: ContentType) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPassword(trimmed) { return (true, .password) }
        if isCreditCard(trimmed) { return (true, .creditCard) }
        if isEmail(trimmed) { return (false, .email) }
        if isURL(trimmed) { return (false, .url) }
        if isPhone(trimmed) { return (false, .phone) }
        if isCode(trimmed) { return (false, .code) }
        if isJSON(trimmed) { return (false, .json) }
        if isTable(trimmed) { return (false, .table) }
        return (false, .text)
    }

    private static func isPassword(_ s: String) -> Bool {
        let patterns = [
            "(?i)(password|passwd|pwd|pass|secret|token|api[_-]?key|access[_-]?key)\\s*[:=]\\s*['\"]?\\S+",
            "(?i)(bearer|basic)\\s+[a-zA-Z0-9\\-._~+/]+=*",
            "^[a-zA-Z0-9+/]{40,}={0,2}$"
        ]
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    private static func isCreditCard(_ s: String) -> Bool {
        let cleaned = s.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression)
        return cleaned.count >= 13 && cleaned.count <= 19 && cleaned.allSatisfy(\.isNumber)
    }

    private static func isEmail(_ s: String) -> Bool {
        s.range(of: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) != nil
    }

    private static func isURL(_ s: String) -> Bool {
        s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("www.")
    }

    private static func isPhone(_ s: String) -> Bool {
        let cleaned = s.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return cleaned.count >= 7 && cleaned.count <= 15 && (s.contains("+") || s.contains("("))
    }

    private static func isCode(_ s: String) -> Bool {
        let codePatterns = ["func ", "class ", "import ", "const ", "let ", "var ", "def ", "function(",
                           "return ", "if (", "for (", "while (", "#include", "// ", "/* ", "=>", "->"]
        return codePatterns.contains { s.contains($0) }
    }

    private static func isJSON(_ s: String) -> Bool {
        (s.hasPrefix("{") && s.hasSuffix("}")) || (s.hasPrefix("[") && s.hasSuffix("]"))
    }

    private static func isTable(_ s: String) -> Bool {
        let lines = s.components(separatedBy: "\n")
        guard lines.count >= 2 else { return false }
        let tabCount = lines.filter { $0.contains("\t") }.count
        let pipeCount = lines.filter { $0.contains("|") }.count
        return tabCount >= 2 || pipeCount >= 2
    }
}

struct ProjectDetector {
    static func detectProject(app: String, bundle: String) -> String {
        let devBundles = ["com.apple.dt.Xcode", "com.jetbrains.intellij", "com.jetbrains.WebStorm",
                         "com.microsoft.VSCode", "com.sublimetext.4", "com.github.atom",
                         "io.hyper.Hyper", "com.apple.Terminal", "com.googlecode.iterm2"]
        let browserBundles = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                             "com.microsoft.edgemac", "com.opera.Opera"]
        let designBundles = ["com.adobe.Photoshop", "com.sketch.SKetch", "com.figma.Desktop"]

        if devBundles.contains(bundle) { return "Development" }
        if browserBundles.contains(bundle) { return "Web" }
        if designBundles.contains(bundle) { return "Design" }
        if app.lowercased().contains("mail") || app.lowercased().contains("message") { return "Communication" }
        if app.lowercased().contains("word") || app.lowercased().contains("pages") || app.lowercased().contains("notion") { return "Documents" }
        return "Other"
    }
}
