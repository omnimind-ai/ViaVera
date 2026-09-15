import SwiftUI

struct TOTPAccountRowView: View {
    let account: TOTPAccount
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let time = context.date.timeIntervalSince1970
            let code = try? account.algorithm.code(secret: account.secret, time: time, digits: account.digits, period: account.period)
            let remaining = Double(account.period) - time.truncatingRemainder(dividingBy: Double(account.period))
            VStack(alignment: .leading, spacing: 8) {
                Text(account.issuer.isEmpty ? account.name : account.issuer).font(.headline)
                if !account.issuer.isEmpty { Text(account.name).font(.subheadline).foregroundStyle(.secondary) }
                HStack {
                    Text(code ?? "—").font(.largeTitle.monospacedDigit()).bold().privacySensitive()
                    Spacer()
                    Button(isCopied ? "已复制" : "复制", systemImage: isCopied ? "checkmark" : "doc.on.doc", action: onCopy)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                ProgressView(value: remaining, total: Double(account.period))
                    .accessibilityLabel("\(Int(remaining.rounded(.up))) 秒后更新")
            }
            .padding(.vertical, 4)
        }
    }
}
