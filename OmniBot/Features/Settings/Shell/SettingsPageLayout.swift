import SwiftUI

struct SettingsPageLayout<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    init(
        title: String,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
#if os(macOS)
        Group {
            if Actions.self == EmptyView.self {
                Form {
                    content
                }
                .settingsFormStyle()
                .scrollContentBackground(.hidden)
                .frame(maxWidth: AppDesign.settingsContentMaximumWidth)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    Form {
                        content
                    }
                    .settingsFormStyle()
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: AppDesign.settingsContentMaximumWidth)
                    .frame(maxWidth: .infinity)

                    HStack {
                        Spacer(minLength: AppDesign.compactSpacing)
                        actions
                    }
                    .padding(.horizontal, AppDesign.contentPadding)
                    .frame(minHeight: AppDesign.settingsHeaderMinimumHeight)
                }
            }
        }
        .background(.background)
#else
        Form {
            content
        }
        .settingsFormStyle()
        .scrollContentBackground(.hidden)
        .frame(maxWidth: AppDesign.settingsContentMaximumWidth)
        .frame(maxWidth: .infinity)
        .background(Color("SettingsPageBackground"))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                actions
            }
        }
#endif
    }
}

extension SettingsPageLayout where Actions == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, actions: EmptyView.init, content: content)
    }
}
