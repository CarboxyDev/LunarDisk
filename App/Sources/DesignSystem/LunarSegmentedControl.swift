import SwiftUI

struct LunarSegmentedControlOption<Value: Hashable>: Identifiable {
  let value: Value
  let title: String
  let systemImage: String?

  var id: Value { value }

  init(_ title: String, value: Value, systemImage: String? = nil) {
    self.value = value
    self.title = title
    self.systemImage = systemImage
  }
}

struct LunarSegmentedControl<Value: Hashable>: View {
  let options: [LunarSegmentedControlOption<Value>]
  @Binding var selection: Value
  var minItemWidth: CGFloat? = nil
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 8
  var isEnabled: Bool = true

  @Namespace private var selectionNamespace

  var body: some View {
    HStack(spacing: 8) {
      ForEach(options) { option in
        itemButton(for: option)
      }
    }
    .opacity(isEnabled ? 1 : 0.76)
  }

  private func itemButton(for option: LunarSegmentedControlOption<Value>) -> some View {
    let isSelected = option.value == selection

    return Button {
      guard isEnabled else { return }
      withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
        selection = option.value
      }
    } label: {
      Group {
        if let systemImage = option.systemImage {
          Label(option.title, systemImage: systemImage)
        } else {
          Text(option.title)
        }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(isSelected ? AppTheme.Colors.accentForeground : AppTheme.Colors.textSecondary)
      .lineLimit(1)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .frame(minWidth: minItemWidth)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            isSelected
              ? AppTheme.Colors.accent
              : AppTheme.Colors.surfaceElevated.opacity(0.62)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(
                isSelected
                  ? AppTheme.Colors.accent.opacity(0.85)
                  : AppTheme.Colors.cardBorder,
                lineWidth: 1
              )
          )
          .matchedGeometryEffect(
            id: isSelected ? AnyHashable("lunar-segmented-selection") : AnyHashable(option.id),
            in: selectionNamespace
          )
      }
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(option.title)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}
