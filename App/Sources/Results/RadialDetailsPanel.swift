import CoreScan
import SwiftUI
import Visualization

struct RadialDetailsPanel: View {
  let snapshot: RadialBreakdownInspectorSnapshot?
  let isPinned: Bool
  let onClearPinnedSelection: () -> Void
  let targetHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("Details")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        Spacer(minLength: 8)

        if isPinned {
          Label("Pinned", systemImage: "pin.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.accentForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              Capsule(style: .continuous)
                .fill(AppTheme.Colors.accent)
                .overlay(
                  Capsule(style: .continuous)
                    .stroke(AppTheme.Colors.accent.opacity(0.85), lineWidth: 1)
                )
            )
        }
      }

      Text("Hover to inspect. Right-click the chart to pin or unpin a selection.")
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      if isPinned {
        HStack {
          Spacer(minLength: 0)
          Button("Unpin Selection") {
            onClearPinnedSelection()
          }
          .buttonStyle(LunarSecondaryButtonStyle())
        }
      }

      if let snapshot {
        selectionSummaryBlock(snapshot)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(AppTheme.Colors.surfaceElevated.opacity(0.42))
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(AppTheme.Colors.cardBorder.opacity(0.85), lineWidth: 1)
              )
          )

        Divider()
          .overlay(AppTheme.Colors.cardBorder.opacity(0.8))

        Text("Contains")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textSecondary)

        VStack(spacing: 6) {
          ForEach(snapshot.children) { child in
            inspectorRow(child)
          }
        }
      } else {
        Text("No selection yet.")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(AppTheme.Colors.textSecondary)
          .padding(.vertical, 6)
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

  private func selectionSummaryBlock(_ snapshot: RadialBreakdownInspectorSnapshot) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: snapshot.symbolName)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 15, height: 15)

      VStack(alignment: .leading, spacing: 3) {
        Text(snapshot.label)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textPrimary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text("\(ByteFormatter.string(from: snapshot.sizeBytes)) • \(percentString(snapshot.shareOfRoot))")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(AppTheme.Colors.textTertiary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func inspectorRow(_ child: RadialBreakdownInspectorChild) -> some View {
    let sizeText = child.sizeBytes.map { ByteFormatter.string(from: $0) } ?? ""

    return HStack(spacing: 10) {
      Image(systemName: child.symbolName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(child.isMuted ? 0.56 : 0.88))
        .frame(width: 14, alignment: .center)

      Text(child.label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(child.isMuted ? 0.62 : 1))
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 8)

      Text(sizeText)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textTertiary)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minHeight: 30)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(AppTheme.Colors.surfaceElevated.opacity(child.isMuted ? 0.15 : 0.34))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AppTheme.Colors.cardBorder.opacity(child.isMuted ? 0.5 : 0.85), lineWidth: 1)
        )
    )
  }

  private func percentString(_ share: Double) -> String {
    let clamped = max(0, min(1, share)) * 100
    return "\(String(format: "%.1f", clamped))%"
  }
}
