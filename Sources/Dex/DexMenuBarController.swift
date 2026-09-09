import AppKit
import Combine
import DexCore
import SwiftUI

@MainActor
final class DexMenuBarController: NSObject, ObservableObject, NSMenuDelegate {
  private let model: DexApplicationModel
  private let statusItem: NSStatusItem
  private var cancellables: Set<AnyCancellable> = []
  private lazy var settingsWindowController = DexSettingsWindowController(model: model)
  private lazy var windowDrillCoordinator = WindowDrillCoordinator(model: model.windowDrill)

  init(model: DexApplicationModel) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    configureStatusItem()
    observeModel()
    rebuildMenu()
    _ = windowDrillCoordinator
    DexSettingsPresenter.shared.install { [weak self] in
      self?.presentSettingsWindow()
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    model.startIfNeeded()
    model.store.reload()
    populate(menu)
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = DexLogoMark.templateImage
    button.imagePosition = .imageOnly
    button.toolTip = "Dex"
    statusItem.isVisible = model.isMenuBarItemVisible
  }

  private func observeModel() {
    model.$isMenuBarItemVisible
      .removeDuplicates()
      .sink { [weak self] isVisible in
        self?.statusItem.isVisible = isVisible
      }
      .store(in: &cancellables)

    model.store.$configuration
      .sink { [weak self] _ in self?.rebuildMenu() }
      .store(in: &cancellables)

    model.monitor.$status
      .sink { [weak self] _ in self?.rebuildMenu() }
      .store(in: &cancellables)

    model.executor.$lastResult
      .sink { [weak self] _ in self?.rebuildMenu() }
      .store(in: &cancellables)

    model.windowDrill.$phase
      .sink { [weak self] _ in self?.rebuildMenu() }
      .store(in: &cancellables)
  }

  private func rebuildMenu() {
    let menu = statusItem.menu ?? NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    populate(menu)
    statusItem.menu = menu
  }

  private func populate(_ menu: NSMenu) {
    menu.removeAllItems()

    let configuration = model.store.configuration
    let shortcuts = configuration.shortcuts.filter(\.isEnabled)
    if shortcuts.isEmpty {
      menu.addItem(informationalItem("No shortcuts yet"))
    } else {
      let rowWidth = shortcutRowWidth(
        shortcuts: shortcuts,
        trigger: configuration.trigger
      )
      for shortcut in shortcuts {
        let item = NSMenuItem(
          title: shortcut.name,
          action: #selector(executeShortcut(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = shortcut.id.uuidString
        item.isEnabled = true
        item.view = DexShortcutMenuItemView(
          title: shortcut.name,
          shortcut: shortcut.binding.display(using: configuration.trigger),
          width: rowWidth
        ) { [weak self] in
          self?.model.execute(shortcut)
        }
        menu.addItem(item)
      }
    }

    menu.addItem(.separator())

    let drillTitle = model.windowDrill.phase == .setup
      ? "Window Drill…" : "Show Window Drill"
    menu.addItem(
      actionItem(
        drillTitle,
        systemImage: "rectangle.3.group",
        action: #selector(showWindowDrill)
      )
    )
    menu.addItem(.separator())

    if model.monitor.status == .active {
      let activeItem = informationalItem("Global shortcuts active")
      activeItem.image = menuImage(systemName: "checkmark.circle")
      menu.addItem(activeItem)
    } else {
      menu.addItem(
        actionItem(
          "Enable Global Shortcuts…",
          systemImage: "keyboard",
          action: #selector(enableGlobalShortcuts)
        )
      )
    }

    menu.addItem(
      actionItem(
        "Settings…",
        systemImage: "gearshape",
        action: #selector(showSettings),
        keyEquivalent: ",",
        modifiers: .command
      )
    )
    menu.addItem(
      actionItem(
        "About Dex",
        systemImage: "info.circle",
        action: #selector(showAbout)
      )
    )

    if let result = model.executor.lastResult {
      menu.addItem(.separator())
      menu.addItem(informationalItem(result))
    }

    menu.addItem(.separator())
    menu.addItem(
      actionItem(
        "Quit Dex",
        action: #selector(quit)
      )
    )
  }

  private func shortcutRowWidth(shortcuts: [DexShortcut], trigger: TriggerKey) -> CGFloat {
    let font = NSFont.menuFont(ofSize: 0)

    let titleWidth =
      shortcuts
      .map { ($0.name as NSString).size(withAttributes: [.font: font]).width }
      .max() ?? 0

    let shortcutWidth =
      shortcuts
      .map {
        ($0.binding.display(using: trigger) as NSString)
          .size(withAttributes: [.font: font]).width
      }
      .max() ?? 0
    return max(220, ceil(titleWidth + shortcutWidth + 72))
  }

  private func informationalItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func actionItem(
    _ title: String,
    systemImage: String? = nil,
    action: Selector,
    keyEquivalent: String = "",
    modifiers: NSEvent.ModifierFlags = []
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    item.keyEquivalentModifierMask = modifiers
    item.isEnabled = true
    if let systemImage {
      item.image = menuImage(systemName: systemImage)
    }
    return item
  }

  private func menuImage(systemName: String) -> NSImage? {
    let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
    image?.isTemplate = true
    return image
  }

  @objc private func enableGlobalShortcuts() {
    model.monitor.requestAccess()
  }

  @objc private func executeShortcut(_ sender: NSMenuItem) {
    guard
      let identifier = sender.representedObject as? String,
      let id = UUID(uuidString: identifier),
      let shortcut = model.store.shortcut(id: id)
    else { return }
    model.execute(shortcut)
  }

  @objc private func showSettings() {
    presentSettingsWindow()
  }

  @objc private func showWindowDrill() {
    windowDrillCoordinator.present()
  }

  @objc private func showAbout() {
    NSApplication.shared.activate(ignoringOtherApps: true)

    NSApplication.shared.orderFrontStandardAboutPanel()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func presentSettingsWindow() {
    settingsWindowController.present()
  }
}

@MainActor
final class DexSettingsPresenter {
  static let shared = DexSettingsPresenter()

  private var presentAction: (() -> Void)?

  private init() {}

  func install(_ action: @escaping () -> Void) {
    presentAction = action
  }

  func present() {
    presentAction?()
  }
}

@MainActor
private final class DexSettingsWindowController: NSWindowController {
  init(model: DexApplicationModel) {
    let contentViewController = NSHostingController(rootView: DexSettingsView(model: model))
    let window = NSWindow(contentViewController: contentViewController)
    window.title = "Dex Settings"
    window.styleMask = [.titled, .closable, .resizable]
    window.minSize = NSSize(width: 900, height: 580)
    window.setContentSize(NSSize(width: 900, height: 580))
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    guard let window else { return }
    NSApplication.shared.activate(ignoringOtherApps: true)
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
  }
}

final class DexShortcutMenuItemView: NSView {
  private let title: String
  private let shortcut: String
  private let action: () -> Void

  init(title: String, shortcut: String, width: CGFloat, action: @escaping () -> Void) {
    self.title = title
    self.shortcut = shortcut
    self.action = action
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
    // Native menu items, including the last result, can make the menu wider.
    autoresizingMask = [.width]
    setAccessibilityElement(true)
    setAccessibilityRole(.menuItem)
    setAccessibilityLabel("\(title), \(shortcut)")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let isHighlighted = enclosingMenuItem?.isHighlighted == true
    if isHighlighted {
      NSColor.selectedContentBackgroundColor.setFill()
      NSBezierPath(
        roundedRect: bounds.insetBy(dx: 4, dy: 2),
        xRadius: 4,
        yRadius: 4
      ).fill()
    }

    let font = NSFont.menuFont(ofSize: 0)
    let titleColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
    let shortcutColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
    let baselineY = floor((bounds.height - font.ascender + font.descender) / 2)

    let titleAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: titleColor,
    ]
    let shortcutAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: shortcutColor,
    ]

    (title as NSString).draw(
      at: NSPoint(x: 14, y: baselineY),
      withAttributes: titleAttributes
    )
    let shortcutSize = (shortcut as NSString).size(withAttributes: shortcutAttributes)
    (shortcut as NSString).draw(
      at: NSPoint(x: bounds.width - 14 - shortcutSize.width, y: baselineY),
      withAttributes: shortcutAttributes
    )
  }

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    enclosingMenuItem?.menu?.cancelTracking()
    action()
  }
}
