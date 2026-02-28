import CoreScan
import SwiftUI

struct TrashQueueTrayView: View {
  let trashQueueState: TrashQueueState
  let onReviewAndDelete: () -> Void
  let onRevealInFinder: (String) -> Void
  var lastReport: FileActionBatchReport?

  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      compactBar
      if isExpanded {
        expandedList
      }
    }
    .padding(12)
    .lunarPanelBackground()
    .animation(.easeInOut(duration: 0.18), value: isExpanded)
  }

  private var compactBar: some View {
    HStack(spacing: 10) {
      Image(systemName: "trash")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.red.opacity(0.8))

      Text("\(trashQueueState.count) item\(trashQueueState.count == 1 ? "" : "s")")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textPrimary)

      Text("(\(ByteFormatter.string(from: trashQueueState.totalEstimatedBytes)))")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          isExpanded.toggle()
        }
      } label: {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(AppTheme.Colors.textTertiary)
      }
      .buttonStyle(.plain)
      .help(isExpanded ? "Collapse" : "Expand")

      Spacer(minLength: 8)

      if let lastReport {
        reportBadge(lastReport)
      }

      Button("Clear All") {
        trashQueueState.clear()
      }
      .buttonStyle(LunarSecondaryButtonStyle())

      Button("Review & Delete") {
        onReviewAndDelete()
      }
      .buttonStyle(LunarDestructiveButtonStyle())
    }
  }

  private func reportBadge(_ report: FileActionBatchReport) -> some View {
    let color: Color = report.hasFailures ? .orange : .green
    return Text(report.summary)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(color.opacity(0.12))
          .overlay(
            Capsule(style: .continuous)
              .stroke(color.opacity(0.3), lineWidth: 1)
          )
      )
  }

  private var expandedList: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()
        .overlay(AppTheme.Colors.cardBorder.opacity(0.6))
        .padding(.vertical, 8)

      ScrollView {
        VStack(spacing: 4) {
          ForEach(trashQueueState.items) { item in
            trashQueueRow(item)
          }
        }
      }
      .frame(maxHeight: 200)
    }
  }

  private func trashQueueRow(_ item: TrashQueueItem) -> some View {
    HStack(spacing: 8) {
      Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 1) {
        Text(item.name)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(item.path)
          .font(.system(size: 10, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .lineLimit(1)
          .truncationMode(.head)
      }

      Spacer(minLength: 8)

      if item.isBlocked {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.orange)
          .help("System-critical path — will be skipped")
      }

      Text(ByteFormatter.string(from: item.sizeBytes))
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      Button {
        onRevealInFinder(item.path)
      } label: {
        Image(systemName: "arrow.up.forward.square")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)
      }
      .buttonStyle(.plain)
      .help("Reveal in Finder")

      Button {
        trashQueueState.remove(path: item.path)
      } label: {
        Image(systemName: "minus.circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.red.opacity(0.7))
      }
      .buttonStyle(.plain)
      .help("Remove from queue")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(item.isBlocked ? Color.orange.opacity(0.06) : AppTheme.Colors.surfaceElevated.opacity(0.34))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              item.isBlocked ? Color.orange.opacity(0.3) : AppTheme.Colors.cardBorder.opacity(0.7),
              lineWidth: 1
            )
        )
    )
  }
}
