import SwiftUI

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.subtleBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    var tint: Color = AppTheme.accent

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.2), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.5), lineWidth: 1)
            }
    }
}

