import SwiftUI

struct NativeToolInputView: View {
    let component: NativeToolComponent
    let runtime: NativeToolRuntime
    @State private var text: String
    @State private var number: Double
    @State private var flag: Bool

    init(component: NativeToolComponent, runtime: NativeToolRuntime) {
        self.component = component
        self.runtime = runtime
        let value = component.binding.flatMap { runtime.state[$0] } ?? component.sessionBinding.flatMap { runtime.sessionState[$0] } ?? .null
        _text = State(initialValue: value.stringValue ?? "")
        _number = State(initialValue: value.numberValue ?? 0)
        _flag = State(initialValue: value == .bool(true))
    }

    var body: some View {
        Group {
            switch component.type {
            case .textField:
                TextField(component.title ?? "输入", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            case .secureField:
                SecureField(component.title ?? "密码", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
            case .numberField:
                LabeledContent(component.title ?? "数值") {
                    TextField(component.title ?? "数值", value: $number, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
#if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
#endif
                }
            case .toggle:
                Toggle(component.title ?? "开关", isOn: $flag)
            case .picker:
                Picker(component.title ?? "选择", selection: $text) {
                    ForEach(component.options ?? [], id: \.self) { option in Text(option).tag(option) }
                }
            default: EmptyView()
            }
        }
        .onChange(of: text) { _, value in write(.string(value)) }
        .onChange(of: number) { _, value in write(.number(value)) }
        .onChange(of: flag) { _, value in write(.bool(value)) }
        .onChange(of: component.binding.flatMap { runtime.state[$0] } ?? component.sessionBinding.flatMap { runtime.sessionState[$0] }) { _, value in
            if let value = value?.stringValue { text = value }
            if let value = value?.numberValue { number = value }
            if case let .bool(value) = value { flag = value }
        }
    }

    private func write(_ value: AgentValue) {
        if let key = component.binding { runtime.set(value, for: key) }
        if let key = component.sessionBinding { runtime.setSession(value, for: key) }
    }
}
