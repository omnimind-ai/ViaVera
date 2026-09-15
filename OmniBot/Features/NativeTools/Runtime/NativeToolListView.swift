import SwiftUI

struct NativeToolListView: View {
    let component: NativeToolComponent
    let runtime: NativeToolRuntime

    var body: some View {
        let entries = (component.binding.flatMap { runtime.state[$0]?.arrayValue } ?? runtime.value(component.value).arrayValue ?? []).compactMap(NativeToolListEntry.init)
        LazyVStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                Text(component.title ?? "暂无记录").foregroundStyle(.secondary).padding(.vertical)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(component.children ?? []) { child in
                        NativeToolComponentView(component: child, runtime: runtime, item: entry.value)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
            }
        }
    }
}
