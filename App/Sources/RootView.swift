import AppKit
import CoreScan
import LunardiskAI
import SwiftUI
import Visualization

struct RootView: View {
  @EnvironmentObject private var onboardingState: OnboardingStateStore
  @StateObject private var model = AppModel()

  var body: some View {
    Group {
      if onboardingState.hasCompletedOnboarding {
        scannerView
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
      } else {
        OnboardingView {
          onboardingState.completeOnboarding()
        }
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: onboardingState.hasCompletedOnboarding)
  }

  private var scannerView: some View {
    VStack(alignment: .leading, spacing: 16) {
      controls
      Divider()
      content
    }
    .padding(20)
  }

  private var controls: some View {
    HStack(spacing: 12) {
      Button("Choose Folder") {
        chooseFolder()
      }

      Button("Scan") {
        model.startScan()
      }
      .disabled(model.selectedURL == nil || model.isScanning)

      if model.isScanning {
        Button("Cancel") {
          model.cancelScan()
        }
      }

      Spacer()

      if let selectedURL = model.selectedURL {
        Text(selectedURL.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text("No folder selected")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.isScanning {
      VStack(alignment: .leading, spacing: 12) {
        ProgressView()
        Text("Scanning selected folder...")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else if let rootNode = model.rootNode {
      HStack(alignment: .top, spacing: 24) {
        SunburstChartView(root: rootNode)
          .frame(minWidth: 460, minHeight: 460)

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Top Items")
              .font(.headline)
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rootNode.sortedChildrenBySize.prefix(25))) { child in
                  HStack {
                    Text(child.name)
                      .lineLimit(1)
                    Spacer()
                    Text(ByteFormatter.string(from: child.sizeBytes))
                      .foregroundStyle(.secondary)
                  }
                  .font(.caption)
                }
              }
            }
            .frame(maxHeight: 320)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
              .font(.headline)
            ForEach(model.insights) { insight in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(insight.severity == .warning ? "Warning" : "Info")
                  .font(.caption.bold())
                  .foregroundStyle(insight.severity == .warning ? .orange : .blue)
                Text(insight.message)
                  .font(.caption)
              }
            }
          }
        }
        .frame(maxWidth: 420, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else if let errorMessage = model.errorMessage {
      Text(errorMessage)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      Text("Choose a folder and run a scan to see storage breakdown.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose folder to scan"
    panel.prompt = "Select"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false

    if panel.runModal() == .OK {
      model.selectedURL = panel.url
      model.rootNode = nil
      model.insights = []
      model.errorMessage = nil
    }
  }
}
