import Flutter
import OSLog
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    _ = Diagnostics.launchDate
    // The Config tab's diagnostic log: the system share sheet, this process's own unified log (where
    // the native SDK writes its diagnostics) and the app's identity for the log header.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WirexExampleDiagnostics") {
      let channel = FlutterMethodChannel(name: "wirex.example/diagnostics", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "share":
          let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
          Diagnostics.share(text)
          result(nil)
        case "nativeLog":
          result(Diagnostics.ownLog())
        case "appInfo":
          result(Diagnostics.appInfo())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

enum Diagnostics {
  /// Read once at launch: the unified log is read from here.
  static let launchDate = Date()

  static func share(_ text: String) {
    guard let root = topViewController() else { return }
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = root.view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
    root.present(sheet, animated: true)
  }

  static func appInfo() -> [String: String] {
    let bundle = Bundle.main
    return [
      "appId": bundle.bundleIdentifier ?? "?",
      "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
      "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
      "model": modelIdentifier(),
      "os": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
    ]
  }

  /// This process's unified-log entries since launch: the SDK's (a `com.wirexapp` subsystem),
  /// capped at 4000 lines. Other entries are left out unless they are errors or faults.
  static func ownLog() -> String {
    do {
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let entries = try store.getEntries(at: store.position(date: launchDate)).compactMap { $0 as? OSLogEntryLog }
      let wirex = entries.filter { $0.subsystem.range(of: "wirex", options: .caseInsensitive) != nil || $0.level == .error || $0.level == .fault }
      if wirex.isEmpty { return "(no SDK entry and no error in the unified log this run; \(entries.count) system entries omitted)" }
      let chosen = wirex.suffix(4000)
      let clock = DateFormatter()
      clock.dateFormat = "HH:mm:ss.SSS"
      return chosen.map { "\(clock.string(from: $0.date)) \($0.subsystem)/\($0.category): \($0.composedMessage)" }
        .joined(separator: "\n")
    } catch {
      return "unified log unavailable: \(error)"
    }
  }

  private static func modelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
    return "\(machine) (\(UIDevice.current.model))"
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
