import Cocoa
import CoreGraphics
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var mouseCapture: MouseCaptureController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)
    acceptsMouseMovedEvents = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    mouseCapture = MouseCaptureController(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self
    )

    super.awakeFromNib()
  }
}

/// Spike-only native mouse capture bridge.
///
/// `CGAssociateMouseAndMouseCursorPosition(false)` freezes the system cursor
/// while local NSEvents continue to carry unbounded relative deltaX/deltaY.
final class MouseCaptureController: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private weak var window: NSWindow?
  private var eventSink: FlutterEventSink?
  private var localMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var cursorHidden = false
  private(set) var isCaptured = false

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    methodChannel = FlutterMethodChannel(
      name: "minedart/mouse",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "minedart/mouse/events",
      binaryMessenger: messenger
    )
    self.window = window
    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "deallocated", message: "Mouse controller is gone", details: nil))
        return
      }
      switch call.method {
      case "capture": self.capture(result: result)
      case "release":
        let error = self.release(reason: "dart")
        if error == .success {
          result(nil)
        } else {
          result(FlutterError(
            code: "cg_release_failed",
            message: "CGAssociateMouseAndMouseCursorPosition(true) failed",
            details: error.rawValue
          ))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
    eventChannel.setStreamHandler(self)

    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in self?.release(reason: "app-inactive") })
    observers.append(center.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in self?.release(reason: "window-focus-lost") })
    observers.append(center.addObserver(
      forName: NSWindow.willCloseNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in self?.release(reason: "window-closed") })
  }

  deinit {
    release(reason: "deinit")
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    events(["type": "capture", "captured": isCaptured])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func capture(result: @escaping FlutterResult) {
    dispatchPrecondition(condition: .onQueue(.main))
    if isCaptured {
      result(["captured": true, "alreadyCaptured": true])
      return
    }
    guard NSApp.isActive, window?.isKeyWindow == true else {
      result(FlutterError(
        code: "window_not_focused",
        message: "Activate and focus the app window before capture",
        details: nil
      ))
      return
    }

    let associationError = CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
    guard associationError == .success else {
      result(FlutterError(
        code: "cg_associate_failed",
        message: "CGAssociateMouseAndMouseCursorPosition(false) failed",
        details: associationError.rawValue
      ))
      return
    }

    NSCursor.hide()
    cursorHidden = true
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
    ]) { [weak self] event in
      self?.emit(deltaX: event.deltaX, deltaY: event.deltaY)
      return event
    }
    isCaptured = true
    eventSink?(["type": "capture", "captured": true])
    result(["captured": true, "alreadyCaptured": false])
  }

  private func emit(deltaX: CGFloat, deltaY: CGFloat) {
    guard isCaptured else { return }
    eventSink?([
      "type": "delta",
      "dx": Double(deltaX),
      "dy": Double(deltaY),
    ])
  }

  @discardableResult
  private func release(reason: String) -> CGError {
    dispatchPrecondition(condition: .onQueue(.main))
    guard isCaptured || localMonitor != nil || cursorHidden else { return .success }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    let associationError = CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    if cursorHidden {
      NSCursor.unhide()
      cursorHidden = false
    }
    isCaptured = false
    var stateEvent: [String: Any] = [
      "type": "capture",
      "captured": false,
      "reason": reason,
    ]
    if associationError != .success {
      stateEvent["releaseError"] = associationError.rawValue
    }
    eventSink?(stateEvent)
    return associationError
  }
}
