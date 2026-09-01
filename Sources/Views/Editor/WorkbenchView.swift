import SwiftUI

struct WorkbenchView: View {
  @EnvironmentObject var model: AppModel
  @FocusState var inspectorFocus: InspectorFocus?

  enum InspectorFocus: Hashable {
    case start
    case end
    case text
  }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        transportSection
        subtitleTable
      }

      if model.showInspector {
        Divider()
        inspector
          .frame(width: 300)
          .background(Color(nsColor: .controlBackgroundColor))
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  var transportSection: some View {
    VStack(spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.currentProjectTitle)
            .font(.system(size: 20, weight: .semibold))
          Text(model.currentDocumentName)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        HStack(spacing: 8) {
          Button {
            model.exportArtifacts()
          } label: {
            Label("导出", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(WorkbenchHeaderActionButtonStyle(isProminent: true))
          .disabled(!model.canExport)
          .help("导出当前字幕（⌘E）")

          Button {
            model.showInspector.toggle()
          } label: {
            Label(model.showInspector ? "隐藏右栏" : "显示右栏", systemImage: "sidebar.right")
          }
          .buttonStyle(WorkbenchHeaderActionButtonStyle(isProminent: false))
        }
      }

      HStack {
        HStack(spacing: 14) {
          button("backward.end.fill") { model.skip(by: -2) }
          button(model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayback() }
          button("forward.end.fill") { model.skip(by: 2) }

          Text("\(formatClock(model.currentTime)) / \(formatClock(model.playbackDuration))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }

        Spacer()

        ratePill
      }

      WaveformTimelineView(
        progress: model.playbackDuration > 0
          ? model.currentTime / max(model.playbackDuration, 0.1) : 0,
        samples: model.waveformSamples
      ) { ratio in
        model.seek(to: ratio * model.playbackDuration)
      }
      .frame(height: 88)
    }
    .padding(16)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  var subtitleTable: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        headerCell("#", width: 54)
        headerCell("开始", width: 126)
        headerCell("结束", width: 126)
        headerCell("字幕内容")
        headerCell("", width: 42)
      }
      .background(Color(nsColor: .underPageBackgroundColor))

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
              EditableSubtitleRowView(segment: segment, index: index)
                .id(segment.id)
            }
          }
        }
        .onChange(of: model.selectedSegmentID) { _, segmentID in
          if let segmentID {
            withAnimation(.easeInOut(duration: 0.2)) {
              proxy.scrollTo(segmentID, anchor: .center)
            }
          }
        }
      }
    }
  }
}
