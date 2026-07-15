import Foundation

nonisolated enum TerminalKeyEncoder {
    static func data(
        for key: TerminalKey,
        modifiers: TerminalModifierState = TerminalModifierState(),
        applicationCursor: Bool = false
    ) -> Data {
        switch key {
        case .slash:
            data(for: "/", modifiers: modifiers)
        case .dash:
            data(for: "-", modifiers: modifiers)
        case .escape:
            Data([0x1B])
        case .tab:
            Data([0x09])
        case .home:
            Data([0x1B, 0x5B, 0x48])
        case .arrowUp:
            arrow(direction: 0x41, applicationCursor: applicationCursor)
        case .end:
            Data([0x1B, 0x5B, 0x46])
        case .pageUp:
            Data([0x1B, 0x5B, 0x35, 0x7E])
        case .arrowLeft:
            arrow(direction: 0x44, applicationCursor: applicationCursor)
        case .arrowDown:
            arrow(direction: 0x42, applicationCursor: applicationCursor)
        case .arrowRight:
            arrow(direction: 0x43, applicationCursor: applicationCursor)
        case .pageDown:
            Data([0x1B, 0x5B, 0x36, 0x7E])
        case .enter:
            Data([0x0D])
        case .backspace:
            Data([0x7F])
        }
    }

    private static func arrow(direction: UInt8, applicationCursor: Bool) -> Data {
        Data([0x1B, applicationCursor ? 0x4F : 0x5B, direction])
    }

    static func data(
        for text: String,
        modifiers: TerminalModifierState = TerminalModifierState()
    ) -> Data {
        var result = Data()
        for scalar in text.unicodeScalars {
            if modifiers.isAlternateLocked {
                result.append(0x1B)
            }

            if modifiers.isControlLocked, let controlByte = controlByte(for: scalar) {
                result.append(controlByte)
            } else if scalar.value == 0x0A || scalar.value == 0x0D {
                result.append(0x0D)
            } else {
                result.append(contentsOf: String(scalar).utf8)
            }
        }
        return result
    }

    private static func controlByte(for scalar: Unicode.Scalar) -> UInt8? {
        let value = scalar.value
        if (0x41...0x5A).contains(value) {
            return UInt8(value - 0x40)
        }
        if (0x61...0x7A).contains(value) {
            return UInt8(value - 0x60)
        }

        return switch value {
        case 0x20, 0x40, 0x32:
            0x00
        case 0x5B, 0x33:
            0x1B
        case 0x5C, 0x34:
            0x1C
        case 0x5D, 0x35:
            0x1D
        case 0x5E, 0x36:
            0x1E
        case 0x5F, 0x37:
            0x1F
        case 0x2D:
            0x1F
        case 0x3F, 0x38:
            0x7F
        default:
            nil
        }
    }
}
