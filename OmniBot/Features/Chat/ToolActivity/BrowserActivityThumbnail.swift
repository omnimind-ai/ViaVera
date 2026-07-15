import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct BrowserActivityThumbnail: View {
    @Environment(AppModel.self) private var appModel

    let conversationID: UUID
    let tool: ToolCallPresentation
    let onOpenBrowser: () -> Void

    @State private var previewImage: Image?
    @State private var previewTitle = ""
    @State private var previewURL = ""
    @State private var isLoading = false
#if os(macOS)
    @State private var isShowingBrowser = false
#endif

    var body: some View {
        Button(action: showBrowser) {
            ZStack(alignment: .top) {
                if let previewImage {
                    previewImage
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: AppDesign.toolActivityPreviewWidth,
                            height: AppDesign.toolActivityPreviewHeight,
                            alignment: .top
                        )
                        .clipped()
                } else {
                    browserFallback
                }

                LinearGradient(
                    colors: [
                        .white.opacity(0.28),
                        .clear,
                        .black.opacity(0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .accessibilityHidden(true)

                browserChrome
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
            }
            .frame(
                width: AppDesign.toolActivityPreviewWidth,
                height: AppDesign.toolActivityPreviewHeight
            )
            .background(Color.secondary.opacity(0.10))
            .clipShape(.rect(cornerRadius: AppDesign.compactCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
                    .strokeBorder(Color.primary.opacity(0.10))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .frame(minWidth: AppDesign.minimumTouchTarget, minHeight: AppDesign.minimumTouchTarget)
        .accessibilityLabel("打开当前浏览器")
#if os(macOS)
        .popover(isPresented: $isShowingBrowser, arrowEdge: .bottom) {
            BrowserCardView(conversationID: conversationID)
        }
#endif
        .task(id: tool.id) {
            primeFromTool()
            while !Task.isCancelled {
                await refreshPreview()
                do {
                    try await Task.sleep(for: .milliseconds(1_200))
                } catch {
                    return
                }
            }
        }
    }

    private var browserChrome: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isLoading ? Color.blue : Color.green)
                .frame(width: 4, height: 4)

            Text(hostLabel)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color(red: 0.22, green: 0.32, blue: 0.43))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 11)
        .background(.white.opacity(0.88), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(Color(red: 0.75, green: 0.82, blue: 0.89).opacity(0.55))
        }
    }

    private var browserFallback: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.99, blue: 1),
                Color(red: 0.88, green: 0.93, blue: 0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "safari")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.36, green: 0.50, blue: 0.66))

                Text(hostLabel)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color(red: 0.19, green: 0.32, blue: 0.44))
                    .lineLimit(1)
            }
            .padding(7)
        }
    }

    private var hostLabel: String {
        let trimmedURL = previewURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmedURL), let host = url.host, !host.isEmpty {
            return host
        }
        let trimmedTitle = previewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "浏览器" : trimmedTitle
    }

    private func primeFromTool() {
        previewTitle = tool.browserTitle ?? tool.title
        previewURL = tool.browserURL ?? ""
        isLoading = tool.status == .running
    }

    private func showBrowser() {
#if os(macOS)
        isShowingBrowser = true
#else
        onOpenBrowser()
#endif
    }

    private func refreshPreview() async {
        do {
            guard let frame = try await appModel.browserSession.capturePreviewFrame(
                for: conversationID,
                maximumWidth: 420
            ),
                  let image = platformImage(from: frame.data) else {
                return
            }
            previewImage = image
            if !frame.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                previewTitle = frame.title
            }
            if !frame.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                previewURL = frame.url
            }
            isLoading = frame.isLoading
        } catch {
            // Retain the last good frame. A later refresh can recover while the
            // shared WebKit page is navigating or temporarily unavailable.
        }
    }

    private func platformImage(from data: Data) -> Image? {
#if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
#elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
#endif
    }
}
