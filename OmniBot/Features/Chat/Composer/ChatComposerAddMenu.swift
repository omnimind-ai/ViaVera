import SwiftUI

struct ChatComposerAddMenu: View {
    let isDisabled: Bool
    let onImportAttachments: () -> Void
    let onAddPhotos: () -> Void

    var body: some View {
        Group {
#if os(iOS)
            Menu {
                Button(
                    "引用附件",
                    systemImage: "paperclip",
                    action: onImportAttachments
                )
                Button(
                    "添加照片",
                    systemImage: "photo.on.rectangle",
                    action: onAddPhotos
                )
            } label: {
                ComposerIconLabel(
                    title: "添加",
                    assetName: "ComposerAdd",
                    size: AppDesign.composerIconSize
                )
            }
            .accessibilityLabel("添加")
            .help("添加")
#else
            Button(action: onImportAttachments) {
                ComposerIconLabel(
                    title: "导入附件",
                    assetName: "ComposerAdd",
                    size: AppDesign.composerIconSize
                )
            }
            .accessibilityLabel("导入附件")
            .help("导入附件")
#endif
        }
        .foregroundStyle(.secondary)
        .composerControlFrame()
        .buttonStyle(.borderless)
        .disabled(isDisabled)
    }
}
