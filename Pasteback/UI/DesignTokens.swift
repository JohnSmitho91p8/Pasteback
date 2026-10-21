import SwiftUI

/// Shared presentation values; content/clipboard processing does not depend on them.
enum DesignTokens {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
    enum Radius {
        static let small: CGFloat = 6
        static let card: CGFloat = 10
        static let container: CGFloat = 12
    }
    enum TypeStyle {
        static let title = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 13)
        static let secondary = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let shortcut = Font.system(size: 11, weight: .medium, design: .monospaced)
    }
    enum ColorStyle {
        static let content = Color(nsColor: .controlBackgroundColor)
        static let window = Color(nsColor: .windowBackgroundColor)
        static let selection = Color.accentColor.opacity(0.15)
        static let hover = Color.primary.opacity(0.05)
    }
    enum Metrics {
        static let minimumWindow = CGSize(width: 720, height: 480)
        static let defaultWindow = CGSize(width: 960, height: 600)
        static let thumbnail: CGFloat = 36
        static let rowHeight: CGFloat = 60
        static let statusHeight: CGFloat = 36
        static let emptySymbol: CGFloat = 48
    }
    static let animation = Animation.easeInOut(duration: 0.2)
}
