import SwiftUI

struct UserMessageUnderlineRenderer: TextRenderer {
    let isEnabled: Bool

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: isEnabled ? 2 : 0, trailing: 0)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            context.draw(line)

            let bounds = line.typographicBounds.rect
            guard isEnabled, bounds.width > 0 else { continue }

            // Keep the dash pattern continuous across glyphs and below descenders.
            let underlineY = bounds.maxY + 1
            var underline = Path()
            underline.move(to: CGPoint(x: bounds.minX, y: underlineY))
            underline.addLine(to: CGPoint(x: bounds.maxX, y: underlineY))

            context.stroke(
                underline,
                with: .color(.secondary.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [3, 3])
            )
        }
    }
}
