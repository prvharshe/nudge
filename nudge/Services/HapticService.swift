import UIKit

enum Haptics {
    /// A physical impact — use for button taps and selections.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A success notification — use when an action completes successfully.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
