import SwiftUI

enum AppDesign {
    static let sidebarMinimumWidth: Double = 240
    static let sidebarIdealWidth: Double = 290
    static let sidebarMaximumWidth: Double = 360
    static let sidebarHorizontalInset: Double = 12
#if os(macOS)
    static let sidebarSelectionBackground = Color.accentColor.opacity(0.10)
#endif

    static let chatContentMaximumWidth: Double = 920
    static let composerMaximumWidth: Double = 880
    static let userMessageMaximumWidth: Double = 640
    static let userMessageCornerRadius: Double = 16
    static let userMessageHorizontalPadding: Double = 16
    static let userMessageVerticalPadding: Double = 8
#if os(iOS)
    static let chatBackground = Color(uiColor: .systemBackground)
#else
    static let chatBackground = Color.secondary.opacity(0.025)
#endif

#if os(iOS)
    static let mobileSidebarHorizontalInset: CGFloat = 16
    static let mobileSidebarAvatarSize: CGFloat = 44
    static let mobileSidebarRowVerticalInset: CGFloat = 10
    static let composerMinimumHeight: Double = 92
    static let composerCornerRadius: Double = 24
    static let composerHorizontalInset: Double = 16
    static let composerTextLineHeight: Double = 24
    static let composerMaximumLines = 5
    static let composerControlSize: Double = 44
    static let composerControlSpacing: Double = 6
    static let composerContentBottomPadding: Double = 10
    static let composerContentTopPadding: Double = composerContentBottomPadding + 2
    static let composerContentHorizontalPadding: Double = composerContentTopPadding + 2
    static let composerControlFont = Font.body
    static let composerIconSize: Double = 20
    static let composerTerminalIconSize: Double = 22
#else
    static let composerMinimumHeight: Double = 76
    static let composerCornerRadius: Double = 14
    static let composerHorizontalInset: Double = 20
    static let composerTextLineHeight: Double = 22
    static let composerMaximumLines = 10
    static let composerControlSize: Double = 28
    static let composerControlSpacing: Double = 4
    static let composerContentBottomPadding: Double = 8
    static let composerContentTopPadding: Double = composerContentBottomPadding + 2
    static let composerContentHorizontalPadding: Double = composerContentTopPadding + 2
    static let composerControlFont = Font.callout
    static let composerIconSize: Double = 12
    static let composerTerminalIconSize: Double = 13
    static let macInlineTerminalHeaderHeight: Double = 38
    static let macInlineTerminalHeight: Double = 260
    static let macChatScrollTopFadeHeight: Double = 44
#endif
    static let composerTextFont = Font.body
    static let composerModelControlMaximumWidth: Double = 180
    static let composerBottomPadding: Double = 8

    static let largeCornerRadius: Double = 22
    static let mediumCornerRadius: Double = 16
    static let compactCornerRadius: Double = 12
    static let minimumTouchTarget: Double = 44
    static let toolCapsuleVisualHeight: Double = 34
#if os(iOS)
    static let transcriptStatusMinimumHeight: CGFloat? = minimumTouchTarget
    static let transcriptStatusInlineSpacing: Double = 6
    static let transcriptStatusVerticalPadding: CGFloat = -(
        minimumTouchTarget - toolCapsuleVisualHeight
    ) / 2
#else
    static let transcriptStatusMinimumHeight: CGFloat? = nil
    static let transcriptStatusInlineSpacing: Double = 4
    static let transcriptStatusVerticalPadding: CGFloat = 0
#endif
    static let transcriptReasoningHeaderSpacing: Double = compactSpacing
    static let transcriptReasoningLineOverhang: Double = 2
    static let toolActivityVisualRowHeight: Double = 32
    static let toolActivityPreviewWidth: Double = 94
    static let toolActivityPreviewHeight: Double = 54
    static let toolActivityPreviewOverlap: Double = 30
    static let toolActivityPreviewLeadingInset: Double = 78
    static let toolResultPopoverWidth: Double = 560
    static let toolResultPopoverMinimumHeight: Double = 260
    static let toolResultPopoverIdealHeight: Double = 420
    static let toolResultPopoverMaximumHeight: Double = 560
    static let browserPopoverWidth: Double = 680
    static let browserPopoverHeight: Double = 500

    static let compactSpacing: Double = 8
    static let standardSpacing: Double = 12
    static let sectionSpacing: Double = 18
    static let contentPadding: Double = 20

    static let settingsWindowIdealWidth: Double = 900
    static let settingsWindowIdealHeight: Double = 700
    static let settingsOverlayInset: Double = 20
    static let settingsOverlayCornerRadius: Double = 24
    static let settingsSidebarMinimumWidth: Double = 180
    static let settingsSidebarIdealWidth: Double = 210
    static let settingsSidebarMaximumWidth: Double = 240
    static let settingsContentMaximumWidth: Double = 720
    static let settingsHeaderMinimumHeight: Double = 52
    static let alpinePackageRowMinimumHeight: Double = 24
    static let settingsAutoSaveDelay: Duration = .milliseconds(700)
    static let settingsEditorCornerRadius: Double = 8
    static let settingsEditorPadding: Double = 12

    static let terminalAccessoryColumnCount = 7
    static let terminalAccessoryKeyHeight: Double = 44
    static let terminalEstimatedCharacterWidth: Double = 8.4
    static let terminalEstimatedLineHeight: Double = 20
    static let terminalScreenHorizontalPadding: Double = 12
    static let terminalScreenVerticalPadding: Double = 10
#if os(iOS)
    static let settingsInputMinimumHeight: Double = 44
    static let settingsInputHorizontalPadding: Double = 16
#else
    static let settingsInputMinimumHeight: Double = 24
#endif
}
