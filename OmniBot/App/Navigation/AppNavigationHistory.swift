import Foundation

struct AppNavigationHistory {
    private(set) var current: AppNavigationLocation?
    private var back: [AppNavigationLocation] = []
    private var forward: [AppNavigationLocation] = []

    mutating func visit(_ location: AppNavigationLocation) {
        guard current != location else { return }
        if let current { back.append(current) }
        current = location
        forward.removeAll()
    }

    func canGoBack(where isAvailable: (AppNavigationLocation) -> Bool) -> Bool {
        back.contains { $0 != current && isAvailable($0) }
    }

    func canGoForward(where isAvailable: (AppNavigationLocation) -> Bool) -> Bool {
        forward.contains { $0 != current && isAvailable($0) }
    }

    mutating func goBack(where isAvailable: (AppNavigationLocation) -> Bool) -> AppNavigationLocation? {
        guard canGoBack(where: isAvailable) else { return nil }
        while let location = back.popLast() {
            guard location != current, isAvailable(location) else { continue }
            if let current, isAvailable(current) { forward.append(current) }
            current = location
            return location
        }
        return nil
    }

    mutating func goForward(where isAvailable: (AppNavigationLocation) -> Bool) -> AppNavigationLocation? {
        guard canGoForward(where: isAvailable) else { return nil }
        while let location = forward.popLast() {
            guard location != current, isAvailable(location) else { continue }
            if let current, isAvailable(current) { back.append(current) }
            current = location
            return location
        }
        return nil
    }
}
