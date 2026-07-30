#!/usr/bin/env swift

import AppKit
import WebKit

final class SVGRenderer: NSObject, WKNavigationDelegate {
  private let outputURL: URL
  private let size: CGFloat
  private let webView: WKWebView

  var error: Error?
  var isFinished = false

  init(sourceURL: URL, outputURL: URL, size: CGFloat) {
    self.outputURL = outputURL
    self.size = size
    webView = WKWebView(
      frame: NSRect(x: 0, y: 0, width: size, height: size),
      configuration: WKWebViewConfiguration()
    )
    super.init()

    webView.navigationDelegate = self
    webView.setValue(false, forKey: "drawsBackground")
    webView.loadFileURL(
      sourceURL,
      allowingReadAccessTo: sourceURL.deletingLastPathComponent()
    )
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = webView.bounds
    configuration.snapshotWidth = NSNumber(value: Double(size))

    webView.takeSnapshot(with: configuration) { [self] image, snapshotError in
      defer { isFinished = true }

      if let snapshotError {
        error = snapshotError
        return
      }

      guard
        let image,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else {
        error = NSError(
          domain: "DexSVGRenderer",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Could not encode the SVG snapshot as PNG."]
        )
        return
      }

      do {
        try png.write(to: outputURL)
      } catch {
        self.error = error
      }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    self.error = error
    isFinished = true
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    self.error = error
    isFinished = true
  }
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Double(arguments[3]), size > 0 else {
  fputs("Usage: render-svg.swift <input.svg> <output.png> <size>\n", stderr)
  exit(2)
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

let renderer = SVGRenderer(
  sourceURL: URL(fileURLWithPath: arguments[1]),
  outputURL: URL(fileURLWithPath: arguments[2]),
  size: CGFloat(size)
)
let deadline = Date(timeIntervalSinceNow: 30)

while !renderer.isFinished, Date() < deadline {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}

guard renderer.isFinished else {
  fputs("Timed out while rendering \(arguments[1]).\n", stderr)
  exit(1)
}

if let error = renderer.error {
  fputs("\(error.localizedDescription)\n", stderr)
  exit(1)
}
