import Foundation

public protocol FileScanning: Sendable {
  func scan(at url: URL, maxDepth: Int?) async throws -> FileNode
}

public enum ScanError: Error, LocalizedError {
  case notFound(path: String)
  case unreadable(path: String, underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .notFound(path):
      return "Path not found: \(path)"
    case let .unreadable(path, underlying):
      return "Could not read path \(path): \(underlying.localizedDescription)"
    }
  }
}

public actor DirectoryScanner: FileScanning {
  private let fileManager: FileManager
  private let keys: Set<URLResourceKey> = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .totalFileAllocatedSizeKey,
    .fileAllocatedSizeKey
  ]

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func scan(at url: URL, maxDepth: Int? = nil) async throws -> FileNode {
    try Task.checkCancellation()
    guard fileManager.fileExists(atPath: url.path) else {
      throw ScanError.notFound(path: url.path)
    }
    return try await scanNode(at: url, depth: 0, maxDepth: maxDepth)
  }

  private func scanNode(at url: URL, depth: Int, maxDepth: Int?) async throws -> FileNode {
    try Task.checkCancellation()
    let values = try resourceValues(for: url)
    let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    let isDirectory = values.isDirectory ?? false

    if !isDirectory {
      return FileNode(
        name: name,
        path: url.path,
        isDirectory: false,
        sizeBytes: fileSize(from: values)
      )
    }

    if let maxDepth, depth >= maxDepth {
      return FileNode(
        name: name,
        path: url.path,
        isDirectory: true,
        sizeBytes: try recursiveDirectorySize(at: url),
        children: []
      )
    }

    let childURLs: [URL]
    do {
      try Task.checkCancellation()
      childURLs = try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsPackageDescendants]
      ).sorted { lhs, rhs in
        lhs.path < rhs.path
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ScanError.unreadable(path: url.path, underlying: error)
    }

    var children: [FileNode] = []
    children.reserveCapacity(childURLs.count)

    for childURL in childURLs {
      try Task.checkCancellation()
      let childValues: URLResourceValues
      do {
        childValues = try resourceValues(for: childURL)
      } catch {
        if shouldSkip(error: error) {
          continue
        }
        throw error
      }
      if childValues.isSymbolicLink == true {
        continue
      }
      do {
        let childNode = try await scanNode(at: childURL, depth: depth + 1, maxDepth: maxDepth)
        children.append(childNode)
      } catch {
        if shouldSkip(error: error) {
          continue
        }
        throw error
      }
    }

    let total = children.reduce(Int64(0)) { partialResult, child in
      partialResult + child.sizeBytes
    }

    return FileNode(
      name: name,
      path: url.path,
      isDirectory: true,
      sizeBytes: total,
      children: children
    )
  }

  private func recursiveDirectorySize(at url: URL) throws -> Int64 {
    do {
      try Task.checkCancellation()
      let childURLs = try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsPackageDescendants]
      ).sorted { lhs, rhs in
        lhs.path < rhs.path
      }
      var total: Int64 = 0
      for childURL in childURLs {
        try Task.checkCancellation()
        let values: URLResourceValues
        do {
          values = try resourceValues(for: childURL)
        } catch {
          if shouldSkip(error: error) {
            continue
          }
          throw error
        }
        if values.isSymbolicLink == true {
          continue
        }
        if values.isDirectory == true {
          do {
            total += try recursiveDirectorySize(at: childURL)
          } catch {
            if shouldSkip(error: error) {
              continue
            }
            throw error
          }
          continue
        }
        total += fileSize(from: values)
      }
      return total
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ScanError.unreadable(path: url.path, underlying: error)
    }
  }

  private func resourceValues(for url: URL) throws -> URLResourceValues {
    do {
      return try url.resourceValues(forKeys: keys)
    } catch {
      throw ScanError.unreadable(path: url.path, underlying: error)
    }
  }

  private func fileSize(from values: URLResourceValues) -> Int64 {
    if let fileSize = values.fileSize {
      return Int64(fileSize)
    }
    if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
      return Int64(allocated)
    }
    return 0
  }

  private func shouldSkip(error: Error) -> Bool {
    if case let ScanError.unreadable(_, underlying) = error {
      return shouldSkip(error: underlying)
    }

    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      let recoverableCocoaCodes: Set<Int> = [
        NSFileReadNoPermissionError,
        NSFileReadNoSuchFileError,
        NSFileReadUnknownError,
        NSFileReadInvalidFileNameError
      ]
      return recoverableCocoaCodes.contains(nsError.code)
    }

    if nsError.domain == NSPOSIXErrorDomain {
      let recoverablePosixCodes: Set<Int> = [
        Int(EACCES),
        Int(EPERM),
        Int(ENOENT),
        Int(ENOTDIR),
        Int(EBADF),
        Int(EIO)
      ]
      return recoverablePosixCodes.contains(nsError.code)
    }

    return false
  }
}
