import Foundation
import Testing
@testable import Via_Vera

@Suite("Main window navigation history")
@MainActor
struct AppNavigationHistoryTests {
    private let chat = AppNavigationLocation(destination: .conversation(UUID()))
    private let library = AppNavigationLocation(destination: .tools)
    private let toolID = UUID()

    @Test("The initial page has no history and repeat visits preserve forward history")
    func initialAndRepeatedVisits() {
        var history = AppNavigationHistory()
        #expect(!history.canGoBack { _ in true })
        #expect(!history.canGoForward { _ in true })
        #expect(history.goBack { _ in true } == nil)
        history.visit(chat)
        history.visit(chat)
        #expect(!history.canGoBack { _ in true })
        history.visit(library)
        #expect(history.goBack { _ in true } == chat)
        history.visit(chat)
        #expect(history.goForward { _ in true } == library)
        #expect(history.goForward { _ in true } == nil)
    }

    @Test("Back and forward restore chats, the library, tool details and internal screens")
    func crossesPageBoundaries() {
        let detail = AppNavigationLocation(destination: .tools, nativeToolPath: [toolID])
        let screen = AppNavigationLocation(destination: .tools, nativeToolPath: [toolID], nativeToolScreenID: "accounts")
        let anotherChat = AppNavigationLocation(destination: .conversation(UUID()))
        let pages = [chat, library, detail, screen, anotherChat]
        var history = AppNavigationHistory()
        for page in pages { history.visit(page) }
        for page in pages.dropLast().reversed() {
            #expect(history.goBack { _ in true } == page)
        }
        #expect(!history.canGoBack { _ in true })
        for page in pages.dropFirst() {
            #expect(history.goForward { _ in true } == page)
        }
        #expect(!history.canGoForward { _ in true })
    }

    @Test("Visiting a new page after going back discards the old forward branch")
    func newBranch() {
        var history = AppNavigationHistory()
        history.visit(chat)
        history.visit(library)
        #expect(history.goBack { _ in true } == chat)
        let next = AppNavigationLocation(destination: .conversation(UUID()))
        history.visit(next)
        #expect(!history.canGoForward { _ in true })
        #expect(history.goBack { _ in true } == chat)
        #expect(history.goForward { _ in true } == next)
    }

    @Test("Deleted destinations are skipped in both directions")
    func skipsDeletedPages() {
        let detail = AppNavigationLocation(destination: .tools, nativeToolPath: [toolID])
        let next = AppNavigationLocation(destination: .conversation(UUID()))
        var history = AppNavigationHistory()
        for page in [chat, library, detail, next] { history.visit(page) }
        #expect(history.goBack { $0 != detail } == library)
        #expect(history.goBack { _ in true } == chat)
        #expect(history.goForward { $0 != library } == next)
        #expect(!history.canGoForward { _ in true })
    }

    @Test("Unavailable current pages are not reinserted and empty directions are disabled")
    func unavailableCurrentPage() {
        var history = AppNavigationHistory()
        history.visit(chat)
        history.visit(library)
        #expect(!history.canGoBack { _ in false })
        #expect(history.goBack { _ in false } == nil)
        #expect(history.current == library)
        #expect(history.goBack { $0 != library } == chat)
        #expect(!history.canGoForward { _ in true })
    }

    @Test("Tool state does not create duplicate chat or library entries")
    func canonicalLocations() {
        #expect(AppNavigationLocation(
            destination: chat.destination, nativeToolPath: [toolID], nativeToolScreenID: "accounts"
        ) == chat)
        #expect(AppNavigationLocation(destination: .tools, nativeToolScreenID: "accounts") == library)
    }

    @Test("Every main-window destination can participate in history")
    func allRootDestinations() {
        var history = AppNavigationHistory()
        let destinations: [AppDestination] = [chat.destination, .providers, .soul, .memory, .skills, .runtime, .tools]
        for destination in destinations { history.visit(AppNavigationLocation(destination: destination)) }
        for destination in destinations.dropLast().reversed() {
            #expect(history.goBack { _ in true }?.destination == destination)
        }
    }
}
