import Foundation

// A read-only MCP server (JSON-RPC 2.0 over stdio, one message per line) that serves the state
// Mac Monitor writes after every sample. It can look but never act: there are no fix tools.

let stateDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "MacMonitor/state")
/// Mac Monitor samples every 30 seconds; well past that, it has most likely quit.
let staleAfter: TimeInterval = 5 * 60
let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

struct Tool {
    let name: String
    let description: String
    /// The file Mac Monitor writes for this tool, served as-is.
    let file: String
}

let tools = [
    Tool(name: "get_vitals",
         description: "Mac Monitor's vitals (memory, CPU, disk, battery, uptime, temperature), each with a green/amber/red health, the value and plain-language context shown in the app, plus the raw system numbers behind them.",
         file: "vitals.json"),
    Tool(name: "list_alerts",
         description: "Every alert Mac Monitor has raised, with severity, the explanation shown to the user, the fix buttons the app offers, and whether it's active, snoozed, acknowledged, or hidden in Settings.",
         file: "alerts.json"),
    Tool(name: "get_top_processes",
         description: "The top 10 apps by memory and by CPU, with each app's helper processes grouped under it, raw numbers, PIDs, and bundle paths.",
         file: "processes.json"),
]

func send(_ message: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func reply(_ id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func reply(_ id: Any, errorCode: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": errorCode, "message": message]])
}

func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
    ["content": [["type": "text", "text": text]], "isError": isError]
}

func call(_ tool: Tool) -> [String: Any] {
    guard let data = try? Data(contentsOf: stateDirectory.appending(path: tool.file)),
          let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sampledAt = (state["sampledAt"] as? String).flatMap({ try? Date($0, strategy: .iso8601) })
    else {
        return toolResult("Mac Monitor isn't running, or hasn't finished its first check. Open Mac Monitor and try again.", isError: true)
    }
    let age = Date().timeIntervalSince(sampledAt)
    guard age < staleAfter else {
        return toolResult("Mac Monitor isn't running: its last check was \(Int(age / 60)) minutes ago. Open Mac Monitor and try again.", isError: true)
    }
    // Passed through untouched: re-encoding would turn the app's 926.4 into 926.39999999999998.
    return toolResult("Mac Monitor checked \(Int(age)) seconds ago.\n\n" + String(decoding: data, as: UTF8.self))
}

func handle(_ message: [String: Any]) {
    let method = message["method"] as? String
    // Notifications (no id) never get a reply.
    guard let id = message["id"], !(id is NSNull) else { return }
    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        let requested = params["protocolVersion"] as? String ?? ""
        reply(id, result: [
            "protocolVersion": supportedProtocolVersions.contains(requested) ? requested : supportedProtocolVersions[0],
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "mac-monitor", "version": "1.0"],
            "instructions": "Read-only view of what Mac Monitor sees on this Mac: vitals, alerts, and the heaviest apps. Data comes from the app's most recent check (every 30 seconds). These tools can't change anything; suggest fixes for the user to approve and carry out.",
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
                "annotations": ["readOnlyHint": true, "openWorldHint": false],
            ] as [String: Any]
        }])
    case "tools/call":
        guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
            reply(id, errorCode: -32602, "Unknown tool: \(params["name"] ?? "none")")
            return
        }
        reply(id, result: call(tool))
    default:
        reply(id, errorCode: -32601, "Method not found: \(method ?? "none")")
    }
}

while let line = readLine() {
    guard !line.isEmpty else { continue }
    guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
        send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        continue
    }
    handle(message)
}
