import SwiftUI

struct NativeToolCapabilityPresentation: View {
    let host: NativeToolHostCapabilities

    var body: some View {
        @Bindable var presentation = host.presentation
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: $presentation.request, onDismiss: presentation.dismissed) { request in
                NativeToolSystemSheet(request: request, host: host)
            }
    }
}
