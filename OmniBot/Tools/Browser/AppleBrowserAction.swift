import Foundation

nonisolated enum AppleBrowserAction: String, CaseIterable, Sendable {
    case navigate
    case screenshot
    case click
    case type
    case getText = "get_text"
    case scroll
    case getPageInfo = "get_page_info"
    case executeJavaScript = "execute_js"
    case findElements = "find_elements"
    case hover
    case getReadable = "get_readable"
    case setUserAgent = "set_user_agent"
    case getBackbone = "get_backbone"
    case fetch
    case newTab = "new_tab"
    case closeTab = "close_tab"
    case listTabs = "list_tabs"
    case getCookies = "get_cookies"
    case scrollAndCollect = "scroll_and_collect"
    case goBack = "go_back"
    case goForward = "go_forward"
    case pressKey = "press_key"
    case waitForSelector = "wait_for_selector"

    var isAutomatedInteraction: Bool {
        switch self {
        case .click, .type, .scroll, .executeJavaScript, .hover,
             .setUserAgent, .fetch, .scrollAndCollect, .pressKey,
             .waitForSelector:
            true
        case .navigate, .screenshot, .getText, .getPageInfo,
             .findElements, .getReadable, .getBackbone, .newTab,
             .closeTab, .listTabs, .getCookies, .goBack, .goForward:
            false
        }
    }
}
