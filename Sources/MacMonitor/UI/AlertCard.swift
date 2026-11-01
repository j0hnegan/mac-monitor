import SwiftUI

@MainActor
struct AlertCard: View {
    let alert: Alert
    let engine: MonitorEngine
    /// Runs a fix, asking for confirmation first when the fix needs it.
    let onFix: (Fix) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.kind.symbol)
                .font(.title3)
                .foregroundStyle(alert.severity.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .fontWeight(.medium)
                Text(alert.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    if let primary = alert.fixes.first {
                        IconButton(title: primary.title, help: primary.title) { onFix(primary) }
                    }
                    Spacer()
                    overflowMenu
                }
                .padding(.top, 6)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(alert.fixes.dropFirst()) { fix in
                Button(fix.title) { onFix(fix) }
            }
            Button("Copy for Claude") { ClaudePrompt.copy(for: alert) }
            Divider()
            Button("Snooze for 1 Day") { engine.snooze(alert, until: Date().addingTimeInterval(86_400)) }
            Button("Snooze for 1 Week") { engine.snooze(alert, until: Date().addingTimeInterval(7 * 86_400)) }
            if !alert.fixes.contains(where: { $0.id == "acknowledge" }) {
                Button("I Know") { engine.acknowledge(alert) }
            }
            if let app = alert.app {
                Divider()
                Button("Ignore \(app)") { engine.ignoreApp(app) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .fontWeight(.semibold)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

extension Alert.Kind {
    var symbol: String {
        switch self {
        case .memoryHog, .memoryPressure: "memorychip"
        case .runawayProcess: "cpu"
        case .uptime: "clock.arrow.circlepath"
        case .lowBatteryDegraded: "battery.25"
        case .batteryService: "battery.100"
        case .lowDisk: "internaldrive"
        case .thermal: "thermometer.medium"
        }
    }
}
