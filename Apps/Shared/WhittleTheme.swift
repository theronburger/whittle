import SwiftUI
import WhittleCore

enum WhittleTheme {
    static let accent = Color(red: 0.27, green: 0.67, blue: 0.52)
    static let canvas = Color(red: 0.105, green: 0.12, blue: 0.125)
}

extension AnnotationColor {
    var color: Color {
        switch self {
        case .coral: return Color(red: 0.98, green: 0.36, blue: 0.32)
        case .amber: return Color(red: 1, green: 0.78, blue: 0.29)
        case .mint: return Color(red: 0.35, green: 0.82, blue: 0.64)
        case .blue: return Color(red: 0.32, green: 0.62, blue: 1)
        case .violet: return Color(red: 0.71, green: 0.51, blue: 0.96)
        case .white: return .white
        }
    }
}

struct ConnectionBadge: View {
    let connected: Bool
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(connected ? WhittleTheme.accent : .secondary).frame(width: 6, height: 6)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct CircleIconButton: View {
    let title: String
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(title).help(title)
    }
}
