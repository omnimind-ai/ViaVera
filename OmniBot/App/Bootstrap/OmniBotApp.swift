//
//  OmniBotApp.swift
//  OmniBot
//
//  Created by ocean on 2026/7/10.
//

import SwiftUI
import SwiftData

@main
struct OmniBotApp: App {
    @State private var bootstrap = AppBootstrapModel()
#if os(macOS)
    @State private var menuBarSession = MenuBarChatSession()
#endif

    var body: some Scene {
        WindowGroup(id: AppSceneID.mainWindow, for: String.self) { _ in
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
        } defaultValue: {
            AppSceneID.mainWindow
        }
#if os(macOS)
        .defaultSize(width: 1_180, height: 780)
#endif

#if os(macOS)
        MenuBarExtra {
            if let dependencies = bootstrap.dependencies {
                MenuBarChatView(session: menuBarSession)
                    .environment(dependencies.appModel)
                    .modelContainer(dependencies.modelContainer)
            } else {
                BootstrapFailureView(
                    message: bootstrap.errorMessage ?? "未知启动错误",
                    retry: bootstrap.retry
                )
                .frame(width: 480, height: 360)
            }
        } label: {
            Label("OmniBot", image: .menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("快捷聊天", id: AppSceneID.detachedChat) {
            if let dependencies = bootstrap.dependencies {
                MenuBarChatView(session: menuBarSession, isDetached: true)
                    .environment(dependencies.appModel)
                    .modelContainer(dependencies.modelContainer)
            }
        }
        .defaultSize(width: 480, height: 640)
        .windowResizability(.contentMinSize)
        .windowLevel(menuBarSession.isPinned ? .floating : .normal)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
#endif
    }
}
