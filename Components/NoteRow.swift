import SwiftUI

struct NoteRow: View {
    let note: ResearchNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .imageScale(.small)
                        .accessibilityLabel("Favorite")
                }
            }
            Text(note.body.isEmpty ? "No additional text" : note.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(note.modifiedAt.shortDateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
