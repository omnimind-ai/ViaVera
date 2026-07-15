import SwiftUI

struct WorkspaceBreadcrumbView: View {
    let path: WorkspaceBrowserPath
    let onSelectPath: (WorkspaceBrowserPath) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: AppDesign.compactSpacing) {
                    ForEach(path.breadcrumbPaths) { breadcrumbPath in
                        HStack(spacing: AppDesign.compactSpacing) {
                            if breadcrumbPath == path {
                                Text(breadcrumbPath.title)
                                    .bold()
                                    .lineLimit(1)
                            } else {
                                Button(
                                    breadcrumbPath.title,
                                    action: { onSelectPath(breadcrumbPath) }
                                )
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                                .frame(minWidth: 44, alignment: .leading)
                                .contentShape(.rect)
                                .accessibilityHint("切换到该文件夹")

                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .id(breadcrumbPath.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onAppear {
                scrollToCurrentPath(using: proxy)
            }
            .onChange(of: path) {
                scrollToCurrentPath(using: proxy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前文件夹路径")
    }

    private func scrollToCurrentPath(using proxy: ScrollViewProxy) {
        proxy.scrollTo(path.id, anchor: .trailing)
    }
}
