import Foundation

nonisolated enum TokenCountFormatter {
    static func format(_ value: Int?) -> String {
        guard let value, value > 0 else { return "0" }
        if value >= 1_000_000 {
            return compact(value, divisor: 1_000_000, suffix: "m")
        }
        if value >= 1_000 {
            return compact(value, divisor: 1_000, suffix: "k")
        }
        return value.formatted()
    }

    private static func compact(_ value: Int, divisor: Int, suffix: String) -> String {
        if value.isMultiple(of: divisor) {
            return "\(value / divisor)\(suffix)"
        }
        let formatted = (Double(value) / Double(divisor)).formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(0...1))
        )
        return "\(formatted)\(suffix)"
    }
}
