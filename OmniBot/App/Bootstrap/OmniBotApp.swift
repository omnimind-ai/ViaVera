//
//  OmniBotApp.swift
//  OmniBot
//
//  Created by ocean on 2026/7/10.
//

import SwiftUI
import SwiftData
import Observation

@main
struct OmniBotApp: App {
    @State private var bootstrap = AppBootstrapModel()

    var body: some Scene {
        WindowGroup {
            if let dependencies = bootstrap.dependencies {
                ContentView()
                    .environment(dependencies.appModel)
                    .modelContainer(dependencies.modelContainer)
            } else {
                BootstrapFailureView(
                    message: bootstrap.errorMessage ?? "未知启动错误",
                    retry: bootstrap.retry
                )
            }
        }
#if os(macOS)
        .defaultSize(width: 1_180, height: 780)
#endif
    }
}

@MainActor
@Observable
private final class AppBootstrapModel {
    private(set) var dependencies: AppDependencies?
    private(set) var errorMessage: String?

    init() {
        retry()
    }

    func retry() {
        do {
            dependencies = try AppDependencies.live()
            errorMessage = nil
        } catch {
            dependencies = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct BootstrapFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("OmniBot 无法启动", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text(message)
                    .textSelection(.enabled)
                Text("本地数据没有被自动删除。修复 Application Support/OmniBot 中的数据后可重新尝试。")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("重新尝试", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
