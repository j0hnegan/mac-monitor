# Mac Monitor

A native macOS menu bar app that tells you, at a glance, whether your Mac is healthy. When it isn't, it says what's wrong in one sentence and offers a button that fixes it.

- **Vitals:** memory, CPU, disk, uptime, temperature (and battery, off by default), each with a color and a line of plain-language context.
- **Alerts:** memory hogs, runaway processes, memory pressure, long uptime, low disk, and more, each with a one-click fix and snooze.
- **Lightweight:** samples every 30 seconds in the background (every 4 seconds while the panel is open) at well under 1% CPU.

See [PRD.md](PRD.md) for the full spec and roadmap.

## Requirements

macOS 14 or later. Builds with the Xcode Command Line Tools (Swift 5.10+); full Xcode isn't required.

## Build and install

```bash
./scripts/build-app.sh            # builds build/Mac Monitor.app
./scripts/build-app.sh --install  # also copies it to /Applications
```

The app is ad-hoc signed and registers itself to launch at login on first run (toggle it in Settings).

## Ask Claude about it (MCP)

Mac Monitor ships a read-only MCP server, so Claude can see the same vitals, alerts, and heaviest apps when you want help making sense of an alert. It can look, never act.

```bash
claude mcp add mac-monitor -- "/Applications/Mac Monitor.app/Contents/MacOS/macmon-mcp"
```

For the Claude desktop app, add this to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "mac-monitor": {
      "command": "/Applications/Mac Monitor.app/Contents/MacOS/macmon-mcp"
    }
  }
}
```

Tools: `get_vitals`, `list_alerts`, `get_top_processes`. Data comes from the app's latest check, so Mac Monitor needs to be running.
