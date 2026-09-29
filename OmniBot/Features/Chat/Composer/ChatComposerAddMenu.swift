import SwiftUI

struct ChatComposerAddMenu: View {
    let isDisabled: Bool
    let isEditingUserMessage: Bool
    let onCancelEditing: () -> Void
    let onImportAttachments: () -> Void
    let onAddPhotos: () -> Void

    var body: some View {
        Group {
            if isEditingUserMessage {
                Button(action: onCancelEditing) {
                    ComposerIconLabel(
                        title: String(localized: "取消编辑"),
                        assetName: "ComposerAdd",
                        size: AppDesign.composerIconSize
                    )
                    .rotationEffect(.degrees(45))
                }
                .accessibilityLabel("取消编辑")
                .accessibilityHint("清空输入框并退出编辑状态")
                .help("取消编辑")
            } else {
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
                        title: String(localized: "添加"),
                        assetName: "ComposerAdd",
                        size: AppDesign.composerIconSize
                    )
                }
                .accessibilityLabel("添加")
                .help("添加")
#else
                Button(action: onImportAttachments) {
                    ComposerIconLabel(
                        title: String(localized: "导入附件"),
                        assetName: "ComposerAdd",
                        size: AppDesign.composerIconSize
                    )
                }
                .accessibilityLabel("导入附件")
                .help("导入附件")
#endif
            }
        }
        .foregroundStyle(.secondary)
        .composerControlFrame()
        .buttonStyle(.borderless)
        .disabled(isDisabled && !isEditingUserMessage)
    }
}
