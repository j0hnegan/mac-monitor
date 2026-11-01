import AppKit

/// For when the MCP isn't connected (e.g. a sandboxed Claude): the alert plus Mac Monitor's
/// latest data, ready to paste into any Claude chat.
enum ClaudePrompt {
    static func copy(for alert: Alert) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(for: alert), forType: .string)
    }

    static func text(for alert: Alert) -> String {
        let data = ["alerts.json", "vitals.json", "processes.json"].compactMap { name in
            (try? String(contentsOf: StateFile.directory.appending(path: name), encoding: .utf8)).map { "\(name):\n\($0)" }
        }
        return """
        Mac Monitor flagged this on my Mac: "\(alert.title)". \(alert.detail)

        Explain in plain words what's going on, why it happens, and what I should do. Mac Monitor's latest data is below.

        \(data.joined(separator: "\n\n"))
        """
    }
}
