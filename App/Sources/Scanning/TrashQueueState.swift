import CoreScan
import Foundation
import Observation
import Visualization

struct TrashQueueItem: Identifiable, Equatable {
  let path: String
  let name: String
  let sizeBytes: Int64
  let isDirectory: Bool
  let isBlocked: Bool

  var id: String { path }

  init(path: String, name: String, sizeBytes: Int64, isDirectory: Bool) {
    self.path = path
    self.name = name
    self.sizeBytes = sizeBytes
    self.isDirectory = isDirectory
    self.isBlocked = FileActionService.isBlockedSystemPath(path)
  }

  init(snapshot: RadialBreakdownInspectorSnapshot) {
    self.init(
      path: snapshot.path ?? snapshot.id,
      name: snapshot.label,
      sizeBytes: snapshot.sizeBytes,
      isDirectory: snapshot.isDirectory
    )
  }

  init(node: FileNode) {
    self.init(
      path: node.path,
      name: node.name,
      sizeBytes: node.sizeBytes,
      isDirectory: node.isDirectory
    )
  }
}

struct TrashQueueTrashIntent: Identifiable {
  let id = UUID()
  let items: [TrashQueueItem]

  var actionableItems: [TrashQueueItem] {
    items.filter { !$0.isBlocked }
  }

  var blockedCount: Int {
    items.count - actionableItems.count
  }

  var estimatedBytes: Int64 {
    actionableItems.reduce(0) { $0 + $1.sizeBytes }
  }
}

@Observable
final class TrashQueueState {
  private(set) var items: [TrashQueueItem] = []
  private var itemsByPath: [String: TrashQueueItem] = [:]

  var isEmpty: Bool { items.isEmpty }
  var count: Int { items.count }

  var totalEstimatedBytes: Int64 {
    items.reduce(0) { $0 + $1.sizeBytes }
  }

  var queuedPaths: Set<String> {
    Set(itemsByPath.keys)
  }

  var actionableItems: [TrashQueueItem] {
    items.filter { !$0.isBlocked }
  }

  func contains(path: String) -> Bool {
    itemsByPath[path] != nil
  }

  func add(_ item: TrashQueueItem) {
    guard itemsByPath[item.path] == nil else { return }
    items.append(item)
    itemsByPath[item.path] = item
  }

  func remove(path: String) {
    guard itemsByPath.removeValue(forKey: path) != nil else { return }
    items.removeAll { $0.path == path }
  }

  func toggle(_ item: TrashQueueItem) {
    if contains(path: item.path) {
      remove(path: item.path)
    } else {
      add(item)
    }
  }

  func clear() {
    items.removeAll()
    itemsByPath.removeAll()
  }

  func removeSucceeded(paths: Set<String>) {
    for path in paths {
      itemsByPath.removeValue(forKey: path)
    }
    items.removeAll { paths.contains($0.path) }
  }

  func makeTrashIntent() -> TrashQueueTrashIntent? {
    guard !items.isEmpty else { return nil }
    return TrashQueueTrashIntent(items: items)
  }
}
