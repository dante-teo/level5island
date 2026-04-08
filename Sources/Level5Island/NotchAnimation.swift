import SwiftUI

enum NotchAnimation {
    /// Panel open: refined spring, minimal bounce
    static let open = Animation.spring(response: 0.40, dampingFraction: 0.85)
    /// Panel close: critically damped, no overshoot
    static let close = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// Notification pop: controlled bounce for auto-expand
    static let pop = Animation.spring(response: 0.30, dampingFraction: 0.82)
    /// Micro-interaction: hover states, button highlights
    static let micro = Animation.easeOut(duration: 0.15)
    /// Content reveal: delayed after panel shape expansion
    static let contentReveal = Animation.easeOut(duration: 0.22).delay(0.06)
}
