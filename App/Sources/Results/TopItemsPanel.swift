import CoreScan
import SwiftUI

private let topConsumersDefaultLimit = 25

enum TopConsumersMode: String, CaseIterable, Identifiable {
  case directChildren
  case deepestConsumers

  var id: String { rawValue }

  var longTitle: String {
    switch self {
    case .directChildren:
      return "Direct Items"
    case .deepestConsumers:
      return "Nested Items"
    }
  }

  var shortTitle: String {
    switch self {
    case .directChildren:
      return "Direct"
    case .deepestConsumers:
      return "Nested"
    }
  }

  var helperText: String {
    switch self {
    case .directChildren:
      return "Items directly inside this scanned location."
    case .deepestConsumers:
      return "Largest items inside nested folders."
    }
  }
}

struct TopConsumerEntry: Identifiable {
  let node: FileNode
  var id: String { node.id }
}

@MainActor
final class TopConsumersStore: ObservableObject {
  @Published var mode: TopConsumersMode = .directChildren
  @Published private(set) var entriesByMode: [TopConsumersMode: [TopConsumerEntry]] = [:]

  private var rootSignature: RootSignature?
  private var deepestComputationTask: Task<[FileNode], Never>?
  private var deepestApplyTask: Task<Void, Never>?

  func prepare(for rootNode: FileNode, limit: Int = topConsumersDefaultLimit) {
    let signature = RootSignature(rootNode: rootNode)
    guard rootSignature != signature else { return }
    rootSignature = signature
    primeCache(for: rootNode, signature: signature, limit: limit)
  }

  func reset() {
    rootSignature = nil
    entriesByMode = [:]
    cancelDeepestTasks()
  }

  var isPreparingDeepest: Bool {
    mode == .deepestConsumers && entriesByMode[.deepestConsumers] == nil
  }

  func visibleEntries(limit: Int = topConsumersDefaultLimit) -> [TopConsumerEntry] {
    if let cached = entriesByMode[mode], !cached.isEmpty {
      return Array(cached.prefix(limit))
    }

    if mode == .deepestConsumers, let direct = entriesByMode[.directChildren], !direct.isEmpty {
      return Array(direct.prefix(limit))
    }

    return []
  }

  private func primeCache(for rootNode: FileNode, signature: RootSignature, limit: Int) {
    cancelDeepestTasks()

    entriesByMode[.directChildren] = Self.topNodesBySize(rootNode.children, limit: limit).map {
      TopConsumerEntry(node: $0)
    }
    entriesByMode[.deepestConsumers] = nil

    let rootSnapshot = rootNode
    let deepestTask = Task.detached(priority: .userInitiated) {
      Self.deepestTopNodes(from: rootSnapshot, limit: limit)
    }

    deepestComputationTask = deepestTask
    deepestApplyTask = Task { [weak self] in
      let deepestNodes = await deepestTask.value
      guard let self, !Task.isCancelled else { return }
      guard self.rootSignature == signature else { return }
      self.entriesByMode[.deepestConsumers] = deepestNodes.map { TopConsumerEntry(node: $0) }
    }
  }

  private func cancelDeepestTasks() {
    deepestApplyTask?.cancel()
    deepestComputationTask?.cancel()
    deepestApplyTask = nil
    deepestComputationTask = nil
  }

  nonisolated private static func topNodesBySize(_ nodes: [FileNode], limit: Int) -> [FileNode] {
    guard limit > 0 else { return [] }
    var top: [FileNode] = []
    top.reserveCapacity(limit)

    for node in nodes {
      insertNodeBySize(node, into: &top, limit: limit)
    }

    return top
  }

  nonisolated private static func deepestTopNodes(from rootNode: FileNode, limit: Int) -> [FileNode] {
    guard limit > 0 else { return [] }

    var stack: [(node: FileNode, depth: Int)] = rootNode.children.map { ($0, 1) }
    var topDeep: [FileNode] = []
    var topAny: [FileNode] = []
    topDeep.reserveCapacity(limit)
    topAny.reserveCapacity(limit)

    while let current = stack.popLast() {
      if Task.isCancelled { return [] }

      insertNodeBySize(current.node, into: &topAny, limit: limit)
      if current.depth >= 2 {
        insertNodeBySize(current.node, into: &topDeep, limit: limit)
      }
      if current.node.isDirectory && !current.node.children.isEmpty {
        for child in current.node.children {
          stack.append((child, current.depth + 1))
        }
      }
    }

    return topDeep.isEmpty ? topAny : topDeep
  }

  nonisolated private static func insertNodeBySize(_ node: FileNode, into top: inout [FileNode], limit: Int) {
    if top.count == limit, let last = top.last, node.sizeBytes <= last.sizeBytes {
      return
    }

    var low = 0
    var high = top.count
    while low < high {
      let mid = (low + high) / 2
      if top[mid].sizeBytes < node.sizeBytes {
        high = mid
      } else {
        low = mid + 1
      }
    }
    top.insert(node, at: low)

    if top.count > limit {
      top.removeLast()
    }
  }
}

private struct RootSignature: Equatable {
  let id: String
  let sizeBytes: Int64
  let nodeCount: Int
  let treeFingerprint: Int

  init(rootNode: FileNode) {
    id = rootNode.id
    sizeBytes = rootNode.sizeBytes
    var hasher = Hasher()
    var count = 0
    var stack: [FileNode] = [rootNode]

    while let node = stack.popLast() {
      count += 1
      hasher.combine(node.path)
      hasher.combine(node.name)
      hasher.combine(node.isDirectory)
      hasher.combine(node.sizeBytes)
      hasher.combine(node.children.count)

      let sortedChildren = node.children.sorted { lhs, rhs in
        lhs.path < rhs.path
      }
      for child in sortedChildren.reversed() {
        stack.append(child)
      }
    }

    nodeCount = count
    treeFingerprint = hasher.finalize()
  }
}

struct TopItemsPanel: View {
  let rootNode: FileNode
  let onRevealInFinder: (String) -> Void

  @StateObject private var store = TopConsumersStore()

  var body: some View {
    let entries = store.visibleEntries()

    VStack(alignment: .leading, spacing: 10) {
      Text("Top Items")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)

      topItemsModePicker

      Text(store.mode.helperText)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(AppTheme.Colors.textTertiary)

      if store.isPreparingDeepest {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading nested items…")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.Colors.textSecondary)
        }
      }

      if entries.isEmpty {
        Text("No items found in this scan.")
          .font(AppTheme.Typography.body)
          .foregroundStyle(AppTheme.Colors.textTertiary)
      } else {
        List(entries) { entry in
          TopItemsRow(entry: entry) {
            onRevealInFinder(entry.node.path)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 300, alignment: .topLeading)
        .animation(nil, value: store.mode)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lunarPanelBackground()
    .onAppear {
      store.prepare(for: rootNode)
    }
    .onChange(of: rootRefreshKey) { _, _ in
      store.prepare(for: rootNode)
    }
    .onDisappear {
      store.reset()
    }
  }

  private var rootRefreshKey: String {
    "\(rootNode.id)|\(rootNode.sizeBytes)|\(rootNode.children.count)"
  }

  private var topItemsModePicker: some View {
    ViewThatFits(in: .horizontal) {
      modePicker(useShortLabels: false)
      modePicker(useShortLabels: true)
    }
  }

  private func modePicker(useShortLabels: Bool) -> some View {
    Picker("Top Items Scope", selection: $store.mode) {
      Text(useShortLabels ? TopConsumersMode.directChildren.shortTitle : TopConsumersMode.directChildren.longTitle)
        .tag(TopConsumersMode.directChildren)
      Text(useShortLabels ? TopConsumersMode.deepestConsumers.shortTitle : TopConsumersMode.deepestConsumers.longTitle)
        .tag(TopConsumersMode.deepestConsumers)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }
}

private struct TopItemsRow: View {
  let entry: TopConsumerEntry
  let onReveal: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: entry.node.isDirectory ? "folder.fill" : "doc.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .frame(width: 14)

      Text(entry.node.name)
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .lineLimit(1)

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

      Text(ByteFormatter.string(from: entry.node.sizeBytes))
        .font(AppTheme.Typography.body)
        .foregroundStyle(AppTheme.Colors.textSecondary)
    }
    .help(entry.node.path)
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
