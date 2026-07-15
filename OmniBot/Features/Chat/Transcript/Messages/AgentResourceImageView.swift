import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AgentResourceImageView: View {
    private static let maximumImageBytes = 32 * 1_024 * 1_024

    @Environment(AppModel.self) private var appModel
    @Environment(\.openURL) private var openURL
    @State private var image: Image?
    @State private var didFail = false

    let title: String
    let resourceURL: URL

    var body: some View {
        Group {
            if let image {
                Button(action: openResource) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 420, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint("打开资源预览")
            } else if didFail {
                Button(title, systemImage: "photo", action: openResource)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityLabel("正在载入 \(title)")
            }
        }
        .task(id: resourceURL) {
            await loadImage()
        }
    }

    private func openResource() {
        openURL(resourceURL)
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFail = false
        do {
            let resourceProtocol = appModel.resourceProtocol
            let maximumImageBytes = Self.maximumImageBytes
            let data = try await Task.detached(priority: .userInitiated) {
                try resourceProtocol.readData(
                    resourceURL,
                    maximumBytes: maximumImageBytes
                )
            }.value

            #if os(macOS)
            guard let platformImage = NSImage(data: data) else {
                throw AgentResourceImageError.invalidImageData
            }
            image = Image(nsImage: platformImage)
            #else
            guard let platformImage = UIImage(data: data) else {
                throw AgentResourceImageError.invalidImageData
            }
            image = Image(uiImage: platformImage)
            #endif
        } catch {
            didFail = true
        }
    }
}

nonisolated private enum AgentResourceImageError: Error, Sendable {
    case invalidImageData
}
