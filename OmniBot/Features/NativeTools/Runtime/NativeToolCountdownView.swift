import SwiftUI

struct NativeToolCountdownView: View {
    let component: NativeToolComponent
    let runtime: NativeToolRuntime
    let item: AgentValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let deadline = runtime.value(component.value, item: item, now: context.date).numberValue ?? 0
            let seconds = Int(min(315_360_000, max(0, deadline - context.date.timeIntervalSince1970)).rounded(.up))
            LabeledContent(component.title ?? "剩余时间") {
                Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                    .font(.title.monospacedDigit())
                    .accessibilityLabel("\(seconds / 60) 分 \(seconds % 60) 秒")
            }
        }
    }
}
