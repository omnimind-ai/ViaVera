import SwiftUI

/// Type erasure is limited to the recursive boundary of the validated component tree.
struct NativeToolComponentView: View {
    let component: NativeToolComponent
    let runtime: NativeToolRuntime
    var item: AgentValue = .null

    var body: some View {
        if component.visibleWhen == nil || NativeToolExpression.truthy(runtime.value(component.visibleWhen, item: item)) {
            renderedComponent
        }
    }

    private var renderedComponent: AnyView {
        let text = component.value.map { NativeToolExpression.display(runtime.value($0, item: item)) } ?? component.title ?? ""
        switch component.type {
        case .text:
            return AnyView(Text(text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled))
        case .heading:
            return AnyView(Text(text).font(.title2).bold().accessibilityAddTraits(.isHeader))
        case .value:
            return AnyView(LabeledContent(component.title ?? "", value: text).monospacedDigit())
        case .divider:
            return AnyView(Divider())
        case .stack:
            return AnyView(VStack(alignment: .leading, spacing: 12) { children })
        case .row:
            return AnyView(ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) { children }
                VStack(alignment: .leading, spacing: 12) { children }
            })
        case .section:
            return AnyView(GroupBox(component.title ?? "") {
                VStack(alignment: .leading, spacing: 12) { children }.frame(maxWidth: .infinity, alignment: .leading)
            })
        case .textField, .secureField, .numberField, .toggle, .picker:
            return AnyView(NativeToolInputView(component: component, runtime: runtime))
        case .button:
            return AnyView(Button(component.title ?? "执行", action: perform).buttonStyle(.bordered).frame(minHeight: 44))
        case .list:
            return AnyView(NativeToolListView(component: component, runtime: runtime))
        case .progress:
            let progress = min(1, max(0, runtime.value(component.value, item: item).numberValue ?? 0))
            return AnyView(ProgressView(component.title ?? "进度", value: progress))
        case .countdown:
            return AnyView(NativeToolCountdownView(component: component, runtime: runtime, item: item))
        case .totp:
            return AnyView(Text("此旧版组件需要升级为能力调用工具包。").foregroundStyle(.secondary))
        }
    }

    private var children: some View {
        ForEach(component.children ?? []) { child in
            NativeToolComponentView(component: child, runtime: runtime, item: item)
        }
    }

    private func perform() {
        if let action = component.action { runtime.perform(action, item: item) }
    }
}
