import SwiftUI

struct NativeToolLibraryRow: View {
    let record: NativeToolRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: record.package.symbol ?? "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.1), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.package.name).font(.headline)
                if record.builtInID != nil {
                    Text("内置").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = record.package.summary, !summary.isEmpty {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if record.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("已收藏")
            }
        }
        .padding(.vertical, 6)
    }
}
