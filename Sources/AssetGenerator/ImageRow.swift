import SwiftUI

/// One entry in the list: the image preview (part 2) alongside its metadata (part 3).
struct ImageRow: View {
    @Binding var item: DroppedImage

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 78, alignment: .leading)
                    TextField("Name", text: $item.exportName)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }
                detail("Size", item.formattedSize)
                detail("Extension", item.ext)
                detail("Resolution", item.resolution)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}
