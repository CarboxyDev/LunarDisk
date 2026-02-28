import CoreScan
import SwiftUI

struct SearchResultsPanel: View {
  let result: FileNodeSearchResult?
  let query: String
  let isSearching: Bool
  let onRevealInFinder: (String) -> Void
  let targetHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header

      if isSearching {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Searching…")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.Colors.textSecondary)
        }
      } else if let result, !result.matches.isEmpty {
        resultsList(result.matches)
      } else if !query.isEmpty {
        Text("No matches for \"\(query)\"")
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .frame(
      maxWidth: .infinity,
      minHeight: targetHeight > 0 ? targetHeight : nil,
      maxHeight: targetHeight > 0 ? targetHeight : nil,
      alignment: .topLeading
    )
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Search Results")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      if let result, !result.matches.isEmpty {
        Text("\(result.totalMatchCount) \(result.totalMatchCount == 1 ? "match" : "matches") — \(ByteFormatter.string(from: result.totalMatchBytes)) total")
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }
    }
  }

  private func resultsList(_ matches: [FileNodeSearchMatch]) -> some View {
    List(matches, id: \.node.id) { match in
      SearchResultRow(match: match) {
        onRevealInFinder(match.node.path)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.clear)
    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct SearchResultRow: View {
  let match: FileNodeSearchMatch
  let onReveal: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: match.node.isDirectory ? "folder.fill" : "doc.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 2) {
        Text(match.node.name)
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)

        Text(match.node.path)
          .font(.system(size: 10, weight: .regular, design: .monospaced))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      Button(action: onReveal) {
        Image(systemName: "arrow.up.forward.square")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .frame(width: 18, height: 18)
          .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(AppTheme.Colors.surfaceElevated.opacity(0.75))
          )
      }
      .buttonStyle(.plain)
      .help("Reveal in Finder")
      .opacity(isHovered ? 1 : 0)
      .disabled(!isHovered)
      .accessibilityHidden(!isHovered)

      Text(ByteFormatter.string(from: match.node.sizeBytes))
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
    }
    .help(match.node.path)
    .contextMenu {
      Button("Reveal in Finder", action: onReveal)
    }
    .onHover { isHovering in
      isHovered = isHovering
    }
    .padding(.vertical, 4)
    .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
    .listRowBackground(Color.clear)
  }
}
