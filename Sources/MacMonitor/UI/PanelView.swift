import SwiftUI

@MainActor
struct PanelView: View {
    let engine: MonitorEngine
    let openSettings: () -> Void
    @State private var pendingFix: (fix: Fix, alert: Alert)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vitals")
                    .font(.title3.weight(.medium))
                Spacer()
                headerButtons
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 10)

            Divider()
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                ForEach(engine.visibleVitals) { vital in
                    VitalRow(vital: vital, isExpanded: engine.expandedVital == vital.kind) {
                        withAnimation(.snappy(duration: 0.22)) {
                            engine.expandedVital = engine.expandedVital == vital.kind ? nil : vital.kind
                        }
                    }
                }
            }
            .padding(.horizontal, 6)

            if !engine.visibleAlerts.isEmpty {
                sectionHeader("Alerts")
                alerts
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 10)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        // Take exactly the window's height and pin content to the top, so while the window animates,
        // extra content spills off the bottom (revealed as it grows) instead of being centered.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        // The panel gives keyboard focus to its first control on open; the ring reads as a selection.
        .focusEffectDisabled()
        .alert(pendingFix?.fix.title ?? "", isPresented: Binding(
            get: { pendingFix != nil },
            set: { if !$0 { pendingFix = nil } }
        ), presenting: pendingFix) { pending in
            Button(pending.fix.title, role: .destructive) { run(pending.fix, on: pending.alert) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.fix.confirmation ?? "")
        }
    }

    private var alerts: some View {
        VStack(spacing: 8) {
            ForEach(engine.visibleAlerts) { alert in
                AlertCard(alert: alert, engine: engine) { fix in
                    if fix.confirmation != nil {
                        pendingFix = (fix, alert)
                    } else {
                        run(fix, on: alert)
                    }
                }
            }
        }
    }

    private func run(_ fix: Fix, on alert: Alert) {
        Task { await engine.run(fix, on: alert) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var headerButtons: some View {
        HStack(spacing: 2) {
            IconButton(systemImage: "slider.horizontal.3", help: "Settings", action: openSettings)
            IconButton(systemImage: "arrow.clockwise", title: "Rescan", help: "Check everything again now") {
                engine.sample()
            }
        }
    }
}

private struct VitalRow: View {
    let vital: Vital
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    private var isExpandable: Bool { !vital.details.isEmpty }

    var body: some View {
        Button { if isExpandable { toggle() } } label: {
            VStack(alignment: .leading, spacing: 2) {
                // Center-aligned so the dot sits in the middle of the first line.
                HStack(spacing: 10) {
                    Circle()
                        .fill(vital.health.color)
                        .frame(width: 8, height: 8)
                    Text(vital.kind.rawValue)
                    Spacer()
                    Text(vital.value)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let context = vital.context {
                        Text(context)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(vital.details, id: \.self) { Text($0) }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered && isExpandable ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension Health {
    var color: Color {
        switch self {
        case .green: .green
        case .amber: .orange
        case .red: .red
        }
    }
}
