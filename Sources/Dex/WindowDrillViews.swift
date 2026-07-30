import AppKit
import Charts
import Combine
import DexCore
import SwiftUI

@MainActor
final class WindowDrillPresenter {
  static let shared = WindowDrillPresenter()
  private var presentAction: (() -> Void)?

  private init() {}

  func install(_ action: @escaping () -> Void) {
    presentAction = action
  }

  func present() {
    presentAction?()
  }
}

struct WindowDrillCommands: Commands {
  var body: some Commands {
    CommandMenu("Practice") {
      Button("Window Drill…") {
        WindowDrillPresenter.shared.present()
      }
      .keyboardShortcut("d", modifiers: [.command, .option])
    }
  }
}

private enum DrillStyle {
  static let canvas = Color(red: 0.055, green: 0.063, blue: 0.071)
  static let surface = Color(red: 0.09, green: 0.102, blue: 0.112)
  static let line = Color.white.opacity(0.14)
  static let text = Color.white.opacity(0.94)
  static let secondary = Color.white.opacity(0.58)
  static let signal = Color(red: 0.71, green: 0.91, blue: 0.25)
  static let pending = Color(red: 0.91, green: 0.28, blue: 0.22)
  static let warning = Color(red: 1.0, green: 0.63, blue: 0.24)
}

struct WindowDrillSetupView: View {
  @ObservedObject var model: WindowDrillModel

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if !model.hasAccessibilityAccess {
        permissionView
      } else {
        setupContent
      }
    }
    .frame(minWidth: 840, minHeight: 700)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { model.refresh() }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      DexLogoMark()
        .frame(width: 26, height: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text("Window Drill")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
        Text("Train the Dex → Magnet handoff.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Label(
        "\(model.displays.count) display\(model.displays.count == 1 ? "" : "s") detected",
        systemImage: "display.2"
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      Button {
        model.refresh()
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .help("Refresh windows and displays")
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 18)
  }

  private var permissionView: some View {
    ContentUnavailableView {
      Label("Accessibility Access Needed", systemImage: "hand.raised")
    } description: {
      Text("Window Drill reads window positions to score each round automatically. Dex never moves a window for you.")
    } actions: {
      Button("Open Accessibility Settings") {
        model.requestAccessibilityAccess()
      }
      .buttonStyle(.borderedProminent)
      Button("Check Again") { model.refresh() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var setupContent: some View {
    HSplitView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Practice windows")
            .font(.headline)
          Spacer()
          Text("\(model.selectedWindowIDs.count)/\(model.maximumWindowCount)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)

        Divider()

        if model.candidates.isEmpty {
          ContentUnavailableView(
            "No Windows Found",
            systemImage: "macwindow",
            description: Text("Open the apps you want to practice, then refresh.")
          )
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
              ForEach(candidateGroups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 6) {
                  Text(group.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                  ForEach(group.windows) { candidate in
                    candidateRow(candidate)
                  }
                }
              }
            }
            .padding(16)
          }
        }
      }
      .frame(minWidth: 360, idealWidth: 410)

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Detected arrangement")
            .font(.headline)
          MonitorMapView(displays: model.displays, round: nil, completedIDs: [])
            .frame(height: 130)
          Text(model.displays.map(\.name).joined(separator: "  ·  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Divider()

        VStack(alignment: .leading, spacing: 14) {
          settingPicker("Rounds", selection: $model.roundCount, values: [5, 10, 15])
          settingPicker("Seconds per round", selection: $model.secondsPerRound, values: [20, 30, 45])
          overlayDisplayPicker
          Toggle("Success sound", isOn: $model.soundEnabled)
            .toggleStyle(.switch)
        }

        Divider()

        VStack(alignment: .leading, spacing: 10) {
          Text("Layout types")
            .font(.headline)
          Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
              layoutFamilyToggle(.fullScreen)
              layoutFamilyToggle(.halves)
            }
            GridRow {
              layoutFamilyToggle(.thirds)
              layoutFamilyToggle(.twoThirds)
            }
            GridRow {
              layoutFamilyToggle(.quarters)
              Color.clear.frame(height: 1)
            }
          }
          if let message = model.layoutSelectionMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          Label(
            model.magnetShortcuts.zoneShortcuts.isEmpty
              ? "Magnet shortcuts not found"
              : "Magnet shortcuts loaded",
            systemImage: model.magnetShortcuts.zoneShortcuts.isEmpty
              ? "exclamationmark.triangle" : "checkmark.circle"
          )
          .foregroundStyle(
            model.magnetShortcuts.zoneShortcuts.isEmpty ? Color.orange : Color.green
          )
          .font(.callout.weight(.medium))
          Text("Each round uses a subset of your selected windows. Dex verifies a stable match and advances automatically.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let errorMessage = model.errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
        }

        Spacer()

        Button {
          model.start()
        } label: {
          Text("Start drill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canStartDrill)
      }
      .padding(22)
      .frame(minWidth: 330, idealWidth: 370)
    }
  }

  private var candidateGroups: [(name: String, windows: [DrillWindowCandidate])] {
    let groups = Dictionary(grouping: model.candidates) { $0.descriptor.applicationName }
    return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
  }

  private func candidateRow(_ candidate: DrillWindowCandidate) -> some View {
    let selected = model.selectedWindowIDs.contains(candidate.id)
    let dexShortcut = model.dexShortcut(for: candidate.descriptor)
    return Button {
      model.toggleSelection(candidate.id)
    } label: {
      HStack(spacing: 10) {
        Image(nsImage: candidate.applicationIcon)
          .resizable()
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(candidate.descriptor.windowTitle)
            .lineLimit(1)
          Text(dexShortcut.map { "Dex  \($0)" } ?? "No Dex app shortcut")
            .font(.caption)
            .foregroundStyle(dexShortcut == nil ? Color.orange : Color.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Color.accentColor : Color.secondary)
          .font(.system(size: 17))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, 5)
    .accessibilityLabel(
      "\(selected ? "Selected" : "Not selected"), \(candidate.descriptor.applicationName), \(candidate.descriptor.windowTitle)"
    )
  }

  private func settingPicker(
    _ title: String,
    selection: Binding<Int>,
    values: [Int]
  ) -> some View {
    HStack {
      Text(title)
      Spacer()
      Picker(title, selection: selection) {
        ForEach(values, id: \.self) { Text("\($0)").tag($0) }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 170)
    }
  }

  private var overlayDisplayPicker: some View {
    HStack {
      Text("Overlay screen")
      Spacer()
      Picker("Overlay screen", selection: $model.overlayDisplayID) {
        Text("Main display").tag(WindowDrillModel.mainOverlayDisplayID)
        Divider()
        ForEach(model.displays) { display in
          Text(display.name).tag(display.id)
        }
      }
      .labelsHidden()
      .frame(width: 190)
    }
  }

  private func layoutFamilyToggle(_ family: DrillLayoutFamily) -> some View {
    Toggle(
      family.displayName,
      isOn: Binding(
        get: { model.selectedLayoutFamilies.contains(family) },
        set: { enabled in
          if enabled {
            model.selectedLayoutFamilies.insert(family)
          } else {
            model.selectedLayoutFamilies.remove(family)
          }
        }
      )
    )
    .toggleStyle(.checkbox)
  }
}

struct WindowDrillOverlayView: View {
  @ObservedObject var model: WindowDrillModel

  var body: some View {
    Group {
      if case .interrupted(let message) = model.phase {
        interruptedView(message: message)
      } else if model.phase == .finished {
        resultsView
      } else {
        roundView
      }
    }
    .padding(18)
    .frame(width: 430, height: 620, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(DrillStyle.canvas)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(DrillStyle.line, lineWidth: 1)
        )
    )
    .foregroundStyle(DrillStyle.text)
    .preferredColorScheme(.dark)
  }

  private var roundView: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Window Drill")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
          Text("Round \(model.currentRoundIndex + 1) of \(model.rounds.count)")
            .font(.caption)
            .foregroundStyle(DrillStyle.secondary)
        }
        Spacer()
        Text("\(Int(ceil(model.timeRemaining)))")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(model.timeRemaining < 8 ? DrillStyle.warning : DrillStyle.signal)
        Text("s")
          .font(.caption)
          .foregroundStyle(DrillStyle.secondary)
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.1))
          Capsule()
            .fill(DrillStyle.signal)
            .frame(width: proxy.size.width * model.progress)
        }
      }
      .frame(height: 5)

      if model.phase == .playing {
        HStack(spacing: 7) {
          Image(
            systemName: model.verificationState == .verifying
              ? "scope" : "eye"
          )
          Text(model.verificationMessage)
          Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(
          model.verificationState == .verifying
            ? DrillStyle.signal : DrillStyle.secondary
        )
        .accessibilityLabel(model.verificationMessage)
      }

      MonitorMapView(
        displays: model.displays,
        round: model.currentRound,
        completedIDs: model.completedAssignmentIDs
      )
      .frame(height: 170)

      if case .roundComplete(let success) = model.phase {
        HStack {
          Image(systemName: success ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
          Text(success ? "Layout locked" : "Time — next round")
            .fontWeight(.semibold)
          Spacer()
          Text("+\(model.roundScore)")
            .monospacedDigit()
        }
        .foregroundStyle(success ? DrillStyle.signal : DrillStyle.warning)
      }

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(model.currentRound?.assignments ?? []) { assignment in
            assignmentRow(assignment)
            if assignment.id != model.currentRound?.assignments.last?.id {
              Divider().overlay(DrillStyle.line)
            }
          }
        }
      }
      .frame(height: 220)

      HStack {
        if let previous = model.magnetShortcuts.previousDisplayShortcut,
          let next = model.magnetShortcuts.nextDisplayShortcut
        {
          Label("Move display  \(previous)  \(next)", systemImage: "rectangle.2.swap")
            .font(.caption)
            .foregroundStyle(DrillStyle.secondary)
        }
        Spacer()
        Text("\(model.score) pts")
          .font(.callout.weight(.semibold))
          .monospacedDigit()
        Button("Skip") { model.skipRound() }
          .buttonStyle(.plain)
          .foregroundStyle(DrillStyle.secondary)
        Button("End") { model.stop() }
          .buttonStyle(.plain)
          .foregroundStyle(DrillStyle.secondary)
      }
    }
  }

  private func assignmentRow(_ assignment: DrillAssignment) -> some View {
    let complete = model.completedAssignmentIDs.contains(assignment.id)
    let screenName = model.display(for: assignment)?.name ?? "Display"
    let magnetShortcut = model.magnetShortcuts.zoneShortcuts[assignment.zone]
    let dexShortcut = model.dexShortcut(for: assignment.window)
    return HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 3)
        .fill(complete ? DrillStyle.signal : DrillStyle.pending)
        .frame(width: 7, height: 34)
      VStack(alignment: .leading, spacing: 2) {
        Text(assignment.window.applicationName)
          .font(.callout.weight(.semibold))
        Text(assignment.window.windowTitle)
          .font(.caption)
          .foregroundStyle(DrillStyle.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text("\(assignment.zone.displayName) · \(screenName)")
          .font(.caption.weight(.medium))
          .lineLimit(1)
        HStack(spacing: 7) {
          if let dexShortcut { KeyHint(label: "DEX", shortcut: dexShortcut) }
          if let magnetShortcut { KeyHint(label: "MAG", shortcut: magnetShortcut) }
        }
      }
      if complete {
        Image(systemName: "checkmark")
          .foregroundStyle(DrillStyle.signal)
          .fontWeight(.bold)
      }
    }
    .padding(.vertical, 9)
  }

  private var resultsView: some View {
    VStack(spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Drill complete")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
          Text("Session saved to your practice history")
            .font(.caption)
            .foregroundStyle(DrillStyle.secondary)
        }
        Spacer()
        DexLogoMark().frame(width: 24, height: 24)
      }

      Divider().overlay(DrillStyle.line)

      HStack(alignment: .top, spacing: 0) {
        resultMetric(value: "\(model.score)", label: "points", color: DrillStyle.signal)
        resultMetric(
          value: formattedTime(model.completedSession?.averageRoundTime),
          label: "average round",
          color: DrillStyle.text
        )
        resultMetric(
          value: "\(model.completedSession?.successfulRoundCount ?? 0)/\(model.completedSession?.rounds.count ?? 0)",
          label: "layouts cleared",
          color: DrillStyle.text
        )
      }

      if let comparisonText {
        Text(comparisonText)
          .font(.caption.weight(.medium))
          .foregroundStyle(comparisonIsImprovement ? DrillStyle.signal : DrillStyle.warning)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if !resultFamilies.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
              Text("Placement speed")
                .font(.callout.weight(.semibold))
              ForEach(resultFamilies) { family in
                familyResultRow(family)
              }
            }
          }

          Divider().overlay(DrillStyle.line)

          VStack(alignment: .leading, spacing: 8) {
            Text("Recent pace")
              .font(.callout.weight(.semibold))
            if progressPoints.count >= 2 {
              Chart(progressPoints) { point in
                LineMark(
                  x: .value("Session", point.index),
                  y: .value("Average seconds", point.seconds)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(DrillStyle.signal)
                PointMark(
                  x: .value("Session", point.index),
                  y: .value("Average seconds", point.seconds)
                )
                .foregroundStyle(DrillStyle.signal)
              }
              .chartYScale(domain: .automatic(includesZero: false))
              .chartXAxis(.hidden)
              .chartYAxis {
                AxisMarks(position: .leading) { value in
                  AxisGridLine().foregroundStyle(DrillStyle.line)
                  AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                      Text("\(seconds, specifier: "%.0f")s")
                    }
                  }
                  .foregroundStyle(DrillStyle.secondary)
                }
              }
              .frame(height: 112)
              Text("Last \(progressPoints.count) completed drills · lower is faster")
                .font(.caption2)
                .foregroundStyle(DrillStyle.secondary)
            } else {
              Text("Finish one more drill to start your pace chart.")
                .font(.caption)
                .foregroundStyle(DrillStyle.secondary)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
          }
        }
      }

      if let errorMessage = model.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(DrillStyle.warning)
          .lineLimit(2)
      }

      HStack(spacing: 10) {
        Button("Close") { model.closeResults() }
          .buttonStyle(.bordered)
          .controlSize(.large)
        Button { model.replay() } label: {
          Text("Practice again")
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(DrillStyle.signal)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func resultMetric(value: String, label: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundStyle(color)
        .monospacedDigit()
      Text(label)
        .font(.caption2)
        .foregroundStyle(DrillStyle.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func familyResultRow(_ family: DrillLayoutFamily) -> some View {
    let current = model.completedSession?.averagePlacementTime(for: family)
    let historical = model.historicalAveragePlacementTime(for: family)
    return HStack {
      Text(family.displayName)
        .font(.caption)
      Spacer()
      Text(formattedTime(current))
        .font(.caption.weight(.semibold))
        .monospacedDigit()
      if let current, let historical {
        let delta = current - historical
        Text(delta <= 0 ? "\(formattedTime(abs(delta))) faster" : "+\(formattedTime(delta))")
          .font(.caption2)
          .foregroundStyle(delta <= 0 ? DrillStyle.signal : DrillStyle.warning)
          .frame(width: 72, alignment: .trailing)
      } else {
        Text("new")
          .font(.caption2)
          .foregroundStyle(DrillStyle.secondary)
          .frame(width: 72, alignment: .trailing)
      }
    }
  }

  private var resultFamilies: [DrillLayoutFamily] {
    guard let session = model.completedSession else { return [] }
    let families = Set(session.rounds.flatMap(\.placements).map(\.family))
    return DrillLayoutFamily.allCases.filter(families.contains)
  }

  private var progressPoints: [DrillProgressPoint] {
    model.recentSessions.enumerated().compactMap { offset, session in
      guard let average = session.averageRoundTime else { return nil }
      return DrillProgressPoint(index: offset + 1, seconds: average)
    }
  }

  private var comparisonText: String? {
    guard
      let current = model.completedSession?.averageRoundTime,
      let historical = model.historicalAverageRoundTime
    else { return nil }
    let delta = current - historical
    if abs(delta) < 0.05 { return "Right on your historical average." }
    return delta < 0
      ? "\(formattedTime(abs(delta))) faster than your historical average."
      : "\(formattedTime(delta)) slower than your historical average."
  }

  private var comparisonIsImprovement: Bool {
    guard
      let current = model.completedSession?.averageRoundTime,
      let historical = model.historicalAverageRoundTime
    else { return true }
    return current <= historical
  }

  private func formattedTime(_ interval: TimeInterval?) -> String {
    guard let interval else { return "—" }
    return String(format: interval < 10 ? "%.1fs" : "%.0fs", interval)
  }

  private func interruptedView(message: String) -> some View {
    VStack(spacing: 20) {
      Spacer()
      Image(systemName: "display.trianglebadge.exclamationmark")
        .font(.system(size: 44, weight: .medium))
        .foregroundStyle(DrillStyle.warning)
      Text("Display setup changed")
        .font(.system(size: 23, weight: .semibold, design: .rounded))
      Text(message)
        .multilineTextAlignment(.center)
        .foregroundStyle(DrillStyle.secondary)
        .frame(maxWidth: 320)
      Button("Reconfigure drill") { model.replay() }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct DrillProgressPoint: Identifiable {
  let index: Int
  let seconds: TimeInterval

  var id: Int { index }
}

private struct KeyHint: View {
  let label: String
  let shortcut: String

  var body: some View {
    HStack(spacing: 3) {
      Text(label)
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .foregroundStyle(DrillStyle.secondary)
      Text(shortcut)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
    }
  }
}

private struct MonitorMapView: View {
  let displays: [DrillDisplay]
  let round: DrillRound?
  let completedIDs: Set<String>

  var body: some View {
    GeometryReader { proxy in
      if let bounds = displayBounds {
        let scale = min(
          (proxy.size.width - 16) / max(bounds.width, 1),
          (proxy.size.height - 16) / max(bounds.height, 1)
        )
        let mapWidth = bounds.width * scale
        let mapHeight = bounds.height * scale
        let xOffset = (proxy.size.width - mapWidth) / 2
        let yOffset = (proxy.size.height - mapHeight) / 2

        ZStack(alignment: .topLeading) {
          ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
            let displayX = xOffset + ((display.frame.x - bounds.x) * scale)
            let displayY = yOffset + ((display.frame.y - bounds.y) * scale)
            let displayWidth = display.frame.width * scale
            let displayHeight = display.frame.height * scale

            RoundedRectangle(cornerRadius: 5)
              .fill(DrillStyle.surface)
              .overlay(
                RoundedRectangle(cornerRadius: 5)
                  .stroke(DrillStyle.line, lineWidth: 1)
              )
              .frame(width: displayWidth, height: displayHeight)
              .position(
                x: displayX + (displayWidth / 2),
                y: displayY + (displayHeight / 2)
              )

            Text("\(index + 1)")
              .font(.system(size: 9, weight: .bold, design: .rounded))
              .foregroundStyle(DrillStyle.secondary)
              .position(x: displayX + 10, y: displayY + 10)

            ForEach(assignments(for: display.id)) { assignment in
              let unit = assignment.zone.normalizedFrame
              let tileX = displayX + (displayWidth * unit.x)
              let tileY = displayY + (displayHeight * unit.y)
              let tileWidth = displayWidth * unit.width
              let tileHeight = displayHeight * unit.height
              let complete = completedIDs.contains(assignment.id)
              RoundedRectangle(cornerRadius: 3)
                .fill(
                  (complete ? DrillStyle.signal : DrillStyle.pending).opacity(0.84)
                )
                .overlay(
                  Text(shortName(assignment.window.applicationName))
                    .font(.system(size: max(8, min(12, tileWidth / 7)), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .lineLimit(1)
                    .padding(2)
                )
                .padding(2)
                .frame(width: tileWidth, height: tileHeight)
                .position(x: tileX + (tileWidth / 2), y: tileY + (tileHeight / 2))
            }
          }
        }
      }
    }
    .accessibilityLabel("Target monitor arrangement")
  }

  private var displayBounds: DrillRect? {
    guard let first = displays.first else { return nil }
    let minX = displays.map(\.frame.x).min() ?? first.frame.x
    let minY = displays.map(\.frame.y).min() ?? first.frame.y
    let maxX = displays.map { $0.frame.x + $0.frame.width }.max()
      ?? (first.frame.x + first.frame.width)
    let maxY = displays.map { $0.frame.y + $0.frame.height }.max()
      ?? (first.frame.y + first.frame.height)
    return DrillRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private func assignments(for displayID: String) -> [DrillAssignment] {
    round?.assignments.filter { $0.displayID == displayID } ?? []
  }

  private func shortName(_ name: String) -> String {
    if name.localizedCaseInsensitiveContains("Google Chrome") { return "Chrome" }
    if name.count <= 9 { return name }
    return String(name.prefix(8)) + "…"
  }
}

@MainActor
final class WindowDrillCoordinator {
  private let model: WindowDrillModel
  private var setupController: NSWindowController?
  private var overlayPanel: WindowDrillPanel?
  private var phaseObserver: AnyCancellable?
  private var displayObserver: AnyCancellable?

  init(model: WindowDrillModel) {
    self.model = model
    WindowDrillPresenter.shared.install { [weak self] in
      self?.present()
    }
    phaseObserver = model.$phase
      .dropFirst()
      .removeDuplicates()
      .sink { [weak self] phase in
        Task { @MainActor in self?.handle(phase) }
      }
    displayObserver = model.$displays
      .dropFirst()
      .sink { [weak self] _ in
        Task { @MainActor in
          guard
            let self,
            self.model.phase != .setup,
            self.model.phase != .dismissed
          else { return }
          self.showOverlay(reposition: true)
        }
      }
  }

  func present() {
    if model.phase == .dismissed {
      model.replay()
    } else if model.phase == .setup {
      model.refresh()
      showSetup()
    } else {
      showOverlay(reposition: true)
    }
  }

  private func handle(_ phase: WindowDrillModel.Phase) {
    switch phase {
    case .setup:
      overlayPanel?.orderOut(nil)
      showSetup()
    case .playing, .roundComplete, .finished, .interrupted:
      setupController?.window?.orderOut(nil)
      showOverlay(reposition: overlayPanel?.isVisible != true)
    case .dismissed:
      setupController?.window?.orderOut(nil)
      overlayPanel?.orderOut(nil)
    }
  }

  private func showSetup() {
    let controller: NSWindowController
    if let setupController {
      controller = setupController
    } else {
      let hostingController = NSHostingController(rootView: WindowDrillSetupView(model: model))
      let window = NSWindow(contentViewController: hostingController)
      window.title = "Window Drill"
      window.styleMask = [.titled, .closable, .resizable]
      window.minSize = NSSize(width: 840, height: 700)
      window.setContentSize(NSSize(width: 900, height: 740))
      window.isReleasedWhenClosed = false
      window.tabbingMode = .disallowed
      controller = NSWindowController(window: window)
      setupController = controller
    }
    NSApplication.shared.activate(ignoringOtherApps: true)
    controller.showWindow(nil)
    controller.window?.center()
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private func showOverlay(reposition: Bool) {
    let panel: WindowDrillPanel
    if let overlayPanel {
      panel = overlayPanel
    } else {
      panel = WindowDrillPanel(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 620),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.contentViewController = NSHostingController(
        rootView: WindowDrillOverlayView(model: model)
      )
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.level = .statusBar
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = false
      panel.becomesKeyOnlyIfNeeded = true
      panel.isMovableByWindowBackground = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      overlayPanel = panel
    }

    if reposition, let screen = overlayScreen() {
      center(panel, on: screen)
    }
    panel.orderFrontRegardless()
  }

  private func overlayScreen() -> NSScreen? {
    if model.overlayDisplayID == WindowDrillModel.mainOverlayDisplayID {
      return NSScreen.screens.first
    }
    return NSScreen.screens.first { screen in
      let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      return displayNumber?.stringValue == model.overlayDisplayID
    } ?? NSScreen.screens.first
  }

  private func center(_ panel: NSPanel, on screen: NSScreen) {
    let visibleFrame = screen.visibleFrame
    let panelSize = panel.frame.size
    let proposedX = visibleFrame.midX - (panelSize.width / 2)
    let proposedY = visibleFrame.midY - (panelSize.height / 2)
    let x = min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
    let y = min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

private final class WindowDrillPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
