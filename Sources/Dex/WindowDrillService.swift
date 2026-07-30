import AppKit
import ApplicationServices
import Combine
import DexCore
import Foundation
import UniformTypeIdentifiers

struct DrillWindowCandidate: Identifiable {
  let descriptor: DrillWindow
  let applicationIcon: NSImage
  let element: AXUIElement

  var id: String { descriptor.id }
}

@MainActor
final class WindowDrillSystemService {
  var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

  func requestAccessibilityAccess() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  func displays() -> [DrillDisplay] {
    guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
    return NSScreen.screens.enumerated().map { index, screen in
      let frame = screen.visibleFrame
      let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      return DrillDisplay(
        id: displayNumber?.stringValue ?? "display-\(index)",
        name: screen.localizedName,
        frame: DrillRect(
          x: frame.minX,
          y: primaryHeight - frame.maxY,
          width: frame.width,
          height: frame.height
        )
      )
    }
  }

  func windows() -> [DrillWindowCandidate] {
    guard hasAccessibilityAccess else { return [] }
    let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    var candidates: [DrillWindowCandidate] = []

    let applications = NSWorkspace.shared.runningApplications
      .filter {
        $0.processIdentifier != ownProcessIdentifier
          && !$0.isTerminated
          && $0.activationPolicy == .regular
      }
      .sorted {
        ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "")
          == .orderedAscending
      }

    for application in applications {
      let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
      guard let windows: [AXUIElement] = attribute(kAXWindowsAttribute, of: applicationElement)
      else { continue }

      let standardWindows = windows.filter(isStandardWindow)
      for (index, window) in standardWindows.enumerated() {
        let applicationName = application.localizedName ?? "Application"
        let rawTitle: String? = attribute(kAXTitleAttribute, of: window)
        let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowTitle = title?.isEmpty == false ? title! : "Window \(index + 1)"
        let identifier = "\(application.processIdentifier)-\(CFHash(window))"
        let icon = application.icon ?? NSWorkspace.shared.icon(for: .application)
        candidates.append(
          DrillWindowCandidate(
            descriptor: DrillWindow(
              id: identifier,
              applicationName: applicationName,
              windowTitle: windowTitle,
              bundleIdentifier: application.bundleIdentifier
            ),
            applicationIcon: icon,
            element: window
          )
        )
      }
    }
    return candidates
  }

  func frame(of element: AXUIElement) -> DrillRect? {
    guard
      let position: CGPoint = axValue(kAXPositionAttribute, of: element, type: .cgPoint),
      let size: CGSize = axValue(kAXSizeAttribute, of: element, type: .cgSize)
    else { return nil }
    return DrillRect(
      x: position.x,
      y: position.y,
      width: size.width,
      height: size.height
    )
  }

  private func isStandardWindow(_ window: AXUIElement) -> Bool {
    let role: String? = attribute(kAXRoleAttribute, of: window)
    guard role == kAXWindowRole else { return false }
    let subrole: String? = attribute(kAXSubroleAttribute, of: window)
    return subrole == nil || subrole == kAXStandardWindowSubrole
  }

  private func attribute<Value>(_ name: String, of element: AXUIElement) -> Value? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    else { return nil }
    return value as? Value
  }

  private func axValue<Value>(
    _ name: String,
    of element: AXUIElement,
    type: AXValueType
  ) -> Value? {
    guard let value: AXValue = attribute(name, of: element), AXValueGetType(value) == type
    else { return nil }
    let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
    defer { pointer.deallocate() }
    guard AXValueGetValue(value, type, pointer) else { return nil }
    return pointer.pointee
  }
}

struct MagnetShortcutCatalog {
  private struct Command: Decodable {
    struct KeyboardShortcut: Decodable {
      struct Shortcut: Decodable {
        let carbonModifiers: Int
        let carbonKeyCode: UInt16
      }

      let available: Bool
      let enabled: Bool
      let shortcut: Shortcut?
    }

    let legacyKey: String?
    let specialType: String?
    let keyboardShortcut: KeyboardShortcut
  }

  let zoneShortcuts: [DrillZone: String]
  let previousDisplayShortcut: String?
  let nextDisplayShortcut: String?

  init(defaults: UserDefaults = UserDefaults(suiteName: "com.crowdcafe.windowmagnet") ?? .standard) {
    guard
      let data = defaults.object(forKey: "horizontalCommands") as? Data,
      let commands = try? JSONDecoder().decode([Command].self, from: data)
    else {
      zoneShortcuts = [:]
      previousDisplayShortcut = nil
      nextDisplayShortcut = nil
      return
    }

    var zones: [DrillZone: String] = [:]
    var previous: String?
    var next: String?
    for command in commands where command.keyboardShortcut.available
      && command.keyboardShortcut.enabled
    {
      guard let shortcut = command.keyboardShortcut.shortcut else { continue }
      let display = Self.display(
        keyCode: shortcut.carbonKeyCode,
        modifiers: shortcut.carbonModifiers
      )
      if command.specialType == "previousDisplay" { previous = display }
      if command.specialType == "nextDisplay" { next = display }
      guard let legacyKey = command.legacyKey, let zone = Self.zone(for: legacyKey) else {
        continue
      }
      zones[zone] = display
    }
    zoneShortcuts = zones
    previousDisplayShortcut = previous
    nextDisplayShortcut = next
  }

  private static func zone(for legacyKey: String) -> DrillZone? {
    switch legacyKey {
    case "maximizeWindowComboKey": .full
    case "expandWindowWestComboKey": .leftHalf
    case "expandWindowEastComboKey": .rightHalf
    case "expandWindowNorthComboKey": .topHalf
    case "expandWindowSouthComboKey": .bottomHalf
    case "expandWindowNorthWestComboKey": .topLeft
    case "expandWindowNorthEastComboKey": .topRight
    case "expandWindowSouthWestComboKey": .bottomLeft
    case "expandWindowSouthEastComboKey": .bottomRight
    case "expandWindowLeftThirdComboKey": .leftThird
    case "expandWindowCenterThirdComboKey": .middleThird
    case "expandWindowRightThirdComboKey": .rightThird
    case "expandWindowLeftTwoThirdsComboKey": .leftTwoThirds
    case "expandWindowRightTwoThirdsComboKey": .rightTwoThirds
    default: nil
    }
  }

  private static func display(keyCode: UInt16, modifiers: Int) -> String {
    var parts: [String] = []
    if modifiers & 4096 != 0 { parts.append("⌃") }
    if modifiers & 2048 != 0 { parts.append("⌥") }
    if modifiers & 512 != 0 { parts.append("⇧") }
    if modifiers & 256 != 0 { parts.append("⌘") }
    parts.append(KeyCatalog.key(forCode: keyCode)?.label ?? "Key \(keyCode)")
    return parts.joined()
  }
}

@MainActor
final class WindowDrillModel: ObservableObject {
  enum Phase: Equatable {
    case setup
    case playing
    case roundComplete(success: Bool)
    case finished
    case interrupted(message: String)
    case dismissed
  }

  enum VerificationState: Equatable {
    case watching
    case verifying
    case confirmed
  }

  static let mainOverlayDisplayID = "__main_display__"

  @Published private(set) var candidates: [DrillWindowCandidate] = []
  @Published var selectedWindowIDs: Set<String> = []
  @Published private(set) var displays: [DrillDisplay] = []
  @Published private(set) var phase: Phase = .setup
  @Published private(set) var rounds: [DrillRound] = []
  @Published private(set) var currentRoundIndex = 0
  @Published private(set) var completedAssignmentIDs: Set<String> = []
  @Published private(set) var score = 0
  @Published private(set) var roundScore = 0
  @Published private(set) var streak = 0
  @Published private(set) var timeRemaining: TimeInterval = 30
  @Published private(set) var verificationState: VerificationState = .watching
  @Published private(set) var errorMessage: String?
  @Published private(set) var drillHistory: [WindowDrillSession] = []
  @Published private(set) var completedSession: WindowDrillSession?
  @Published var roundCount: Int {
    didSet { UserDefaults.standard.set(roundCount, forKey: Self.roundCountKey) }
  }
  @Published var secondsPerRound: Int {
    didSet { UserDefaults.standard.set(secondsPerRound, forKey: Self.secondsKey) }
  }
  @Published var overlayDisplayID: String {
    didSet { UserDefaults.standard.set(overlayDisplayID, forKey: Self.overlayDisplayKey) }
  }
  @Published var selectedLayoutFamilies: Set<DrillLayoutFamily> {
    didSet {
      UserDefaults.standard.set(
        selectedLayoutFamilies.map(\.rawValue).sorted(),
        forKey: Self.layoutFamiliesKey
      )
    }
  }
  @Published var soundEnabled: Bool {
    didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.soundEnabledKey) }
  }

  let magnetShortcuts = MagnetShortcutCatalog()
  private let system = WindowDrillSystemService()
  private let shortcutStore: ShortcutStore
  private let historyRepository: WindowDrillHistoryRepository
  private var timer: Timer?
  private var roundStartUptime: TimeInterval = 0
  private var placementElapsedByID: [String: TimeInterval] = [:]
  private var sessionRoundResults: [DrillRoundResult] = []
  private var baselineHistory: [WindowDrillSession] = []
  private var allMatchedSince: TimeInterval?
  private var advanceAfter: TimeInterval?
  private var screenObserver: AnyCancellable?
  private var screenChangeWorkItem: DispatchWorkItem?

  private static let roundCountKey = "windowDrill.roundCount"
  private static let secondsKey = "windowDrill.secondsPerRound"
  private static let overlayDisplayKey = "windowDrill.overlayDisplayID"
  private static let layoutFamiliesKey = "windowDrill.layoutFamilies"
  private static let soundEnabledKey = "windowDrill.soundEnabled"

  init(
    shortcutStore: ShortcutStore,
    historyRepository: WindowDrillHistoryRepository = WindowDrillHistoryRepository()
  ) {
    self.shortcutStore = shortcutStore
    self.historyRepository = historyRepository
    let savedRoundCount = UserDefaults.standard.integer(forKey: Self.roundCountKey)
    let savedSeconds = UserDefaults.standard.integer(forKey: Self.secondsKey)
    roundCount = [5, 10, 15].contains(savedRoundCount) ? savedRoundCount : 10
    secondsPerRound = [20, 30, 45].contains(savedSeconds) ? savedSeconds : 30
    overlayDisplayID = UserDefaults.standard.string(forKey: Self.overlayDisplayKey)
      ?? Self.mainOverlayDisplayID
    if let savedFamilies = UserDefaults.standard.stringArray(forKey: Self.layoutFamiliesKey) {
      selectedLayoutFamilies = Set(savedFamilies.compactMap(DrillLayoutFamily.init(rawValue:)))
    } else {
      selectedLayoutFamilies = Set(DrillLayoutFamily.allCases)
    }
    soundEnabled = UserDefaults.standard.object(forKey: Self.soundEnabledKey) as? Bool ?? true
    drillHistory = (try? historyRepository.load()) ?? []

    screenObserver = NotificationCenter.default.publisher(
      for: NSApplication.didChangeScreenParametersNotification
    )
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
      self?.scheduleDisplayReconciliation()
    }
  }

  deinit {
    timer?.invalidate()
    screenChangeWorkItem?.cancel()
  }

  var hasAccessibilityAccess: Bool { system.hasAccessibilityAccess }
  var maximumWindowCount: Int { displays.count * 4 }
  var currentRound: DrillRound? { rounds.indices.contains(currentRoundIndex) ? rounds[currentRoundIndex] : nil }
  var progress: Double {
    guard let currentRound, !currentRound.assignments.isEmpty else { return 0 }
    return Double(completedAssignmentIDs.count) / Double(currentRound.assignments.count)
  }
  var verificationMessage: String {
    switch verificationState {
    case .watching:
      guard let currentRound else { return "Watching window positions live" }
      return "Watching live · \(completedAssignmentIDs.count)/\(currentRound.assignments.count) placed"
    case .verifying:
      return "Hold that layout — verifying"
    case .confirmed:
      return "Layout verified"
    }
  }
  var canStartDrill: Bool {
    !selectedWindowIDs.isEmpty
      && !selectedLayoutFamilies.isEmpty
      && WindowDrillGenerator.canGenerate(
        windowCount: selectedWindowIDs.count,
        displayCount: displays.count,
        enabledFamilies: selectedLayoutFamilies
      )
  }
  var layoutSelectionMessage: String? {
    guard !selectedLayoutFamilies.isEmpty else {
      return "Choose at least one layout type."
    }
    guard !selectedWindowIDs.isEmpty else { return nil }
    guard WindowDrillGenerator.canGenerate(
      windowCount: selectedWindowIDs.count,
      displayCount: displays.count,
      enabledFamilies: selectedLayoutFamilies
    ) else {
      return "These layout types cannot make a challenge from the selected windows across \(displays.count) displays."
    }
    return nil
  }
  var historicalAverageRoundTime: TimeInterval? {
    WindowDrillStats.averageRoundTime(in: baselineHistory)
  }
  var recentSessions: [WindowDrillSession] {
    Array(drillHistory.suffix(12))
  }

  func refresh() {
    displays = system.displays()
    validateOverlayDisplayChoice()
    candidates = system.windows()
    let validIDs = Set(candidates.map(\.id))
    selectedWindowIDs.formIntersection(validIDs)
    if selectedWindowIDs.isEmpty {
      selectedWindowIDs = Set(candidates.prefix(min(4, maximumWindowCount)).map(\.id))
    }
  }

  func requestAccessibilityAccess() {
    system.requestAccessibilityAccess()
  }

  func toggleSelection(_ id: String) {
    if selectedWindowIDs.contains(id) {
      selectedWindowIDs.remove(id)
    } else if selectedWindowIDs.count < maximumWindowCount {
      selectedWindowIDs.insert(id)
    }
  }

  func start() {
    displays = system.displays()
    let selected = candidates
      .filter { selectedWindowIDs.contains($0.id) }
      .map(\.descriptor)
    guard !selected.isEmpty else {
      errorMessage = "Choose at least one window."
      return
    }
    guard selected.count <= maximumWindowCount else {
      errorMessage = "Choose at most \(maximumWindowCount) windows for this display setup."
      return
    }

    var generator = SystemRandomNumberGenerator()
    rounds = WindowDrillGenerator.generate(
      windows: selected,
      displays: displays,
      roundCount: roundCount,
      enabledFamilies: selectedLayoutFamilies,
      using: &generator
    )
    guard !rounds.isEmpty else {
      errorMessage = layoutSelectionMessage ?? "Choose a compatible set of layout types."
      return
    }
    score = 0
    streak = 0
    currentRoundIndex = 0
    sessionRoundResults = []
    baselineHistory = drillHistory
    completedSession = nil
    errorMessage = nil
    verificationState = .watching
    phase = .playing
    beginCurrentRound()
    startTimer()
  }

  func skipRound() {
    guard phase == .playing else { return }
    finishRound(success: false)
  }

  func stop(message: String? = nil) {
    timer?.invalidate()
    timer = nil
    rounds = []
    completedAssignmentIDs = []
    placementElapsedByID = [:]
    verificationState = .watching
    phase = .setup
    errorMessage = message
    refresh()
  }

  func replay() {
    stop()
  }

  func closeResults() {
    timer?.invalidate()
    timer = nil
    phase = .dismissed
  }

  func historicalAveragePlacementTime(for family: DrillLayoutFamily) -> TimeInterval? {
    WindowDrillStats.averagePlacementTime(for: family, in: baselineHistory)
  }

  func dexShortcut(for window: DrillWindow) -> String? {
    guard let bundleIdentifier = window.bundleIdentifier else { return nil }
    let shortcut = shortcutStore.configuration.shortcuts.first { shortcut in
      guard shortcut.isEnabled, case .launchApplication(let target) = shortcut.action else {
        return false
      }
      if target == bundleIdentifier { return true }
      let expandedTarget = (target as NSString).expandingTildeInPath
      return Bundle(path: expandedTarget)?.bundleIdentifier == bundleIdentifier
    }
    return shortcut?.binding.display(using: shortcutStore.configuration.trigger)
  }

  func display(for assignment: DrillAssignment) -> DrillDisplay? {
    displays.first { $0.id == assignment.displayID }
  }

  private func beginCurrentRound() {
    completedAssignmentIDs = []
    placementElapsedByID = [:]
    roundScore = 0
    timeRemaining = TimeInterval(secondsPerRound)
    roundStartUptime = ProcessInfo.processInfo.systemUptime
    allMatchedSince = nil
    advanceAfter = nil
    verificationState = .watching
    phase = .playing
  }

  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    let now = ProcessInfo.processInfo.systemUptime
    if case .roundComplete = phase {
      if let advanceAfter, now >= advanceAfter { advanceRound() }
      return
    }
    guard phase == .playing, let currentRound else { return }

    let elapsed = now - roundStartUptime
    timeRemaining = max(0, TimeInterval(secondsPerRound) - elapsed)
    let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    var matches: Set<String> = []
    for assignment in currentRound.assignments {
      guard
        let candidate = candidateByID[assignment.window.id],
        let display = display(for: assignment),
        let actual = system.frame(of: candidate.element)
      else { continue }
      let target = assignment.zone.frame(in: display)
      if WindowDrillGeometry.matchesWindow(
        actual: actual,
        target: target,
        for: assignment.zone,
        on: display
      ) {
        matches.insert(assignment.id)
      }
    }
    completedAssignmentIDs = matches
    for id in matches where placementElapsedByID[id] == nil {
      placementElapsedByID[id] = elapsed
    }

    if matches.count == currentRound.assignments.count {
      if let allMatchedSince {
        if now - allMatchedSince >= 0.42 { finishRound(success: true) }
      } else {
        allMatchedSince = now
        verificationState = .verifying
      }
    } else {
      allMatchedSince = nil
      verificationState = .watching
    }

    if timeRemaining <= 0 { finishRound(success: false) }
  }

  private func finishRound(success: Bool) {
    guard phase == .playing, let currentRound else { return }
    let elapsed = min(
      TimeInterval(secondsPerRound),
      max(0, ProcessInfo.processInfo.systemUptime - roundStartUptime)
    )
    let placedPoints = completedAssignmentIDs.count * 150
    let completionPoints = success ? 500 : 0
    let speedPoints = success ? Int(timeRemaining.rounded(.down)) * 20 : 0
    streak = success ? streak + 1 : 0
    let streakPoints = success ? max(0, streak - 1) * 50 : 0
    roundScore = placedPoints + completionPoints + speedPoints + streakPoints
    score += roundScore
    sessionRoundResults.append(
      DrillRoundResult(
        succeeded: success,
        elapsed: elapsed,
        placements: currentRound.assignments.compactMap { assignment in
          guard let placementElapsed = placementElapsedByID[assignment.id] else { return nil }
          return DrillPlacementResult(
            family: assignment.zone.layoutFamily,
            zone: assignment.zone,
            elapsed: placementElapsed
          )
        }
      )
    )
    verificationState = success ? .confirmed : .watching
    phase = .roundComplete(success: success)
    advanceAfter = ProcessInfo.processInfo.systemUptime + 1.15
    if success, soundEnabled {
      NSSound(named: "Tink")?.play()
    }
  }

  private func advanceRound() {
    if currentRoundIndex + 1 >= rounds.count {
      timer?.invalidate()
      timer = nil
      let session = WindowDrillSession(score: score, rounds: sessionRoundResults)
      completedSession = session
      do {
        try historyRepository.append(session)
        drillHistory = try historyRepository.load()
      } catch {
        errorMessage = "Your score is shown, but Dex could not save drill history: \(error.localizedDescription)"
        drillHistory.append(session)
      }
      phase = .finished
    } else {
      currentRoundIndex += 1
      beginCurrentRound()
    }
  }

  private func scheduleDisplayReconciliation() {
    screenChangeWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.reconcileDisplays()
    }
    screenChangeWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
  }

  private func reconcileDisplays() {
    let updatedDisplays = system.displays()
    guard !WindowDrillGeometry.sameDisplayTopology(displays, updatedDisplays) else {
      return
    }

    let previousDisplayIDs = Set(displays.map(\.id))
    let updatedDisplayIDs = Set(updatedDisplays.map(\.id))
    displays = updatedDisplays
    validateOverlayDisplayChoice()

    if phase == .dismissed {
      return
    } else if phase == .setup {
      refresh()
    } else if previousDisplayIDs == updatedDisplayIDs {
      // A resolution, menu-bar, or Dock adjustment changed usable frames but
      // every target display still exists. Continue the drill with new bounds.
      allMatchedSince = nil
      verificationState = .watching
    } else {
      timer?.invalidate()
      timer = nil
      completedAssignmentIDs = []
      verificationState = .watching
      phase = .interrupted(
        message: "Your connected displays changed. Reconfigure the drill for the new arrangement."
      )
    }
  }

  private func validateOverlayDisplayChoice() {
    guard overlayDisplayID != Self.mainOverlayDisplayID else { return }
    if !displays.contains(where: { $0.id == overlayDisplayID }) {
      overlayDisplayID = Self.mainOverlayDisplayID
    }
  }
}
