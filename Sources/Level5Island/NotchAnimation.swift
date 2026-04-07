import SwiftUI

enum NotchAnimation {
    /// 展开面板：refined spring, minimal bounce
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.88)
    /// 收起面板：临界阻尼，无过冲（防止 NotchPanelShape 底边露出刘海）
    static let close = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// 通知弹出：controlled bounce for auto-expand
    static let pop = Animation.spring(response: 0.32, dampingFraction: 0.78)
    /// 微交互：hover 状态变化、按钮高亮等
    static let micro = Animation.easeOut(duration: 0.12)
    /// Content reveal: delayed after panel shape expansion
    static let contentReveal = Animation.easeOut(duration: 0.22).delay(0.06)
}
