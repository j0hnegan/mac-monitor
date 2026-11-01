import SwiftUI

/// A button on a soft rounded background that brightens on hover, like toolbar buttons in Control Center.
/// Shows an icon, a title, or both.
struct IconButton: View {
    var systemImage: String? = nil
    var title: String? = nil
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .fontWeight(.semibold)
                }
                if let title { Text(title) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, title == nil ? 0 : 8)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(isHovered ? 0.18 : 0.08), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(help)
        .accessibilityLabel(title ?? help)
        .onHover { isHovered = $0 }
    }
}
