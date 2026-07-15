import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceBrowserRow: View {
    let item: WorkspaceBrowserItem
    let isPreparingPreview: Bool

    var body: some View {
        Label {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name)
                        .lineLimit(1)

                    if item.kind == .file {
                        Text(item.byteCount, format: .byteCount(style: .file))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if item.kind == .symbolicLink {
                        Text("符号链接")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if item.kind == .other {
                        Text("不支持的文件类型")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: AppDesign.compactSpacing)

                if isPreparingPreview {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在准备预览")
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.kind == .directory ? .blue : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }

    private var systemImage: String {
        switch item.kind {
        case .directory:
            "folder.fill"
        case .symbolicLink:
            "link"
        case .other:
            "questionmark.square.dashed"
        case .file:
            fileSystemImage
        }
    }

    private var fileSystemImage: String {
        guard let contentType = UTType(filenameExtension: item.pathExtension) else {
            return "doc"
        }
        if contentType.conforms(to: .image) { return "photo" }
        if contentType.conforms(to: .movie) { return "film" }
        if contentType.conforms(to: .audio) { return "waveform" }
        if contentType.conforms(to: .pdf) { return "doc.richtext" }
        if contentType.conforms(to: .archive) { return "archivebox" }
        if contentType.conforms(to: .plainText) { return "doc.text" }
        return "doc"
    }
}
