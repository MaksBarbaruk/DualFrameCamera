import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.96, green: 0.78, blue: 0.25)
    static let coral = Color(red: 0.98, green: 0.36, blue: 0.36)
    static let surface = Color.white.opacity(0.09)
    static let subtleBorder = Color.white.opacity(0.14)
    static let backgroundTop = Color(red: 0.08, green: 0.08, blue: 0.11)
    static let backgroundBottom = Color(red: 0.015, green: 0.02, blue: 0.035)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.coral.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )

            RadialGradient(
                colors: [AppTheme.accent.opacity(0.09), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

