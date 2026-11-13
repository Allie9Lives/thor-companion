import Flutter
import UIKit
import Photos
import UserNotifications
import UniformTypeIdentifiers
import Security
import WidgetKit
import ActivityKit

private final class ThorAlertDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var fileResult: FlutterResult?
  private var fileMode = ""
  private let fileAccount = "thor-file-connection"
  private var transferDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("thor-transfers", isDirectory: true) }
  private let thorAlertDelegate = ThorAlertDelegate()
  private var lastWidgetReload = Date.distantPast
  private var lastWidgetSignature = ""
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    UNUserNotificationCenter.current().delegate = thorAlertDelegate
    let aboutRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThorAboutBridge")!
    let aboutChannel = FlutterMethodChannel(name: "com.alan.thorCompanion/about", binaryMessenger: aboutRegistrar.messenger())
    aboutChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "version": result(["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""])
      case "github": UIApplication.shared.open(URL(string: "https://github.com/Allie9Lives")!, options: [:]) { opened in if opened { result(nil) } else { result(FlutterError(code:"open_link",message:"Couldn’t open GitHub.",details:nil)) } }
      default: result(FlutterMethodNotImplemented)
      }
    }
    let filesRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThorFilesBridge")!
    let filesChannel = FlutterMethodChannel(name: "com.alan.thorCompanion/files", binaryMessenger: filesRegistrar.messenger())
    filesChannel.setMethodCallHandler { [weak self] call, result in self?.filesCall(call, result: result) }
    let alertsRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThorBatteryAlertsBridge")!
    let alertsChannel = FlutterMethodChannel(name: "com.alan.thorCompanion/batteryAlerts", binaryMessenger: alertsRegistrar.messenger())
    alertsChannel.setMethodCallHandler { call, result in
      if call.method == "requestPermission" {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
        return
      }
      guard call.method == "show", let args = call.arguments as? [String: String],
          let id = args["id"], ["low10", "low20", "charged80", "plugged", "unplugged", "closedLid", "test"].contains(id),
          let title = args["title"], let body = args["body"], title.count < 160, body.count < 500 else {
        result(FlutterError(code: "battery_alert", message: "Invalid battery notification.", details: nil)); return
      }
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
          DispatchQueue.main.async { result(FlutterError(code: "battery_alert_permission", message: "Allow notifications in iPhone Settings.", details: nil)) }; return
        }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: ["plugged", "charged80", "test"].contains(id) ? "thor_positive.wav" : "thor_warning.wav"))
        let request = UNNotificationRequest(identifier: "thor-battery-" + id, content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request) { error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "battery_alert", message: error.localizedDescription, details: nil)) }
            else { result(nil) }
          }
        }
      }
    }
    let screenshotRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThorScreenshotBridge")!
    let screenshotChannel = FlutterMethodChannel(name: "com.alan.thorCompanion/screenshots", binaryMessenger: screenshotRegistrar.messenger())
    screenshotChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "saveVideo" { self?.saveRecording(call, result: result); return }
      if call.method == "keepAwake" {
        UIApplication.shared.isIdleTimerDisabled = call.arguments as? Bool ?? false
        result(nil); return
      }
      guard call.method == "save", let args = call.arguments as? [String: Any],
            let data = args["png"] as? FlutterStandardTypedData,
            let screen = args["screen"] as? String, ["top", "bottom", "both"].contains(screen),
            data.data.count > 24, data.data.count <= 24 * 1024 * 1024,
            UIImage(data: data.data) != nil else {
        result(FlutterError(code: "screenshot", message: "Invalid screenshot image.", details: nil)); return
      }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
        guard authorization == .authorized || authorization == .limited else {
          DispatchQueue.main.async { result(FlutterError(code: "photos_permission", message: "Allow Thor Companion to add photos in iPhone Settings, then tap Save to Photos.", details: nil)) }; return
        }
        PHPhotoLibrary.shared().performChanges({
          let request = PHAssetCreationRequest.forAsset()
          let options = PHAssetResourceCreationOptions()
          options.originalFilename = "Thor-\(screen)-\(Int(Date().timeIntervalSince1970)).png"
          request.addResource(with: .photo, data: data.data, options: options)
        }) { success, error in
          DispatchQueue.main.async {
            if success { result(nil) }
            else { result(FlutterError(code: "screenshot_save", message: error?.localizedDescription ?? "Could not save screenshot to Photos.", details: nil)) }
          }
        }
      }
    }
    let batteryRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThorBatteryWidgetBridge")!
    let batteryChannel = FlutterMethodChannel(
      name: "com.alan.thorCompanion/batteryWidget", binaryMessenger: batteryRegistrar.messenger())
    batteryChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "startLive" || call.method == "stopLive" {
        if #available(iOS 16.2, *) {
          Task { @MainActor in
            do {
              if call.method == "stopLive" {
                for activity in Activity<ThorBatteryAttributes>.activities {
                  await activity.end(nil, dismissalPolicy: .immediate)
                }
              } else {
                guard UIApplication.shared.applicationState == .active else {
                  throw NSError(domain: "ThorLiveBattery", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open the app to start Live battery."])
                }
                guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                  throw NSError(domain: "ThorLiveBattery", code: 2, userInfo: [NSLocalizedDescriptionKey: "Allow Live Activities for Thor Companion in iPhone Settings."])
                }
                guard let value = BatteryStore.read() else {
                  throw NSError(domain: "ThorLiveBattery", code: 3, userInfo: [NSLocalizedDescriptionKey: "Connect to the Thor and receive a battery reading first."])
                }
                let content = ActivityContent(state: value, staleDate: value.updatedAt.addingTimeInterval(90))
                if Activity<ThorBatteryAttributes>.activities.isEmpty {
                  _ = try Activity.request(attributes: ThorBatteryAttributes(name: "Thor"), content: content, pushType: nil)
                } else {
                  for activity in Activity<ThorBatteryAttributes>.activities { await activity.update(content) }
                }
              }
              result(nil)
            } catch {
              result(FlutterError(code: "live_battery", message: error.localizedDescription, details: nil))
            }
          }
        } else {
          result(FlutterError(code: "unsupported", message: "Live battery needs iOS 16.2 or later.", details: nil))
        }
        return
      }
      guard call.method == "update" || call.method == "clear" else {
        result(FlutterMethodNotImplemented); return
      }
      do {
        var snapshot: BatterySnapshot?
        if call.method == "update" {
          guard let args = call.arguments as? [String: Any],
            let percent = args["percent"] as? NSNumber,
            percent.doubleValue.isFinite, (0...100).contains(percent.doubleValue),
            let ms = args["updatedAtMs"] as? NSNumber, ms.doubleValue.isFinite,
            let charging = args["charging"] as? Bool,
            let connected = args["connected"] as? Bool else {
              result(FlutterError(code: "invalid_battery", message: "Invalid battery snapshot", details: nil)); return
          }
          snapshot = BatterySnapshot(percent: Int(percent.doubleValue.rounded()),
            updatedAt: Date(timeIntervalSince1970: ms.doubleValue / 1000), charging: charging, connected: connected)
        }
        try BatteryStore.write(snapshot)
        if #available(iOS 16.2, *) {
          let latest = snapshot
          Task { @MainActor in
            for activity in Activity<ThorBatteryAttributes>.activities {
              if let latest {
                await activity.update(ActivityContent(state: latest, staleDate: latest.updatedAt.addingTimeInterval(90)))
              } else {
                await activity.end(nil, dismissalPolicy: .immediate)
              }
            }
          }
        }
        let signature = snapshot.map { "\($0.percent)/\($0.charging)/\($0.connected)" } ?? "empty"
        if signature != self?.lastWidgetSignature || Date().timeIntervalSince(self?.lastWidgetReload ?? .distantPast) >= 15 * 60 {
          WidgetCenter.shared.reloadTimelines(ofKind: "ThorBattery")
          self?.lastWidgetReload = Date()
          self?.lastWidgetSignature = signature
        }
        result(nil)
      } catch {
        result(FlutterError(code: "battery_cache", message: error.localizedDescription, details: nil))
      }
    }
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ThorDiagnostics")!
    let channel = FlutterMethodChannel(
      name: "com.alan.thorCompanion/diagnostics", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "append", let message = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ble-diagnostics.log")
      let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
      do {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if !FileManager.default.fileExists(atPath: url.path) || size > 1_000_000 {
          try Data().write(to: url, options: .atomic)
        }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: Data(line.utf8))
        NSLog("%@", line)
        result(nil)
      } catch {
        result(FlutterError(code: "log_write", message: error.localizedDescription, details: nil))
      }
    }
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  private func filesCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.alan.thorCompanion.files", kSecAttrAccount as String: fileAccount]
    do {
      try FileManager.default.createDirectory(at: transferDirectory, withIntermediateDirectories: true)
      switch call.method {
      case "cacheDirectory": result(transferDirectory.path)
      case "iconCacheDirectory":
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("thor-app-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        result(directory.path)
      case "forgetConnection": SecItemDelete(query as CFDictionary); result(nil)
      case "saveConnection":
        guard let args = call.arguments as? [String: Any] else { throw NSError(domain:"ThorFiles",code:1) }
        let data = try JSONSerialization.data(withJSONObject: args)
        var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw NSError(domain:"ThorFiles",code:2) }
        result(nil)
      case "loadConnection":
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &found)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess, let data = found as? Data else { throw NSError(domain:"ThorFiles",code:3) }
        result(try JSONSerialization.jsonObject(with: data))
      case "pickFile", "saveFile":
        guard fileResult == nil else { result(FlutterError(code:"files_busy",message:"A Files picker is already open.",details:nil)); return }
        let picker: UIDocumentPickerViewController
        if call.method == "pickFile" { picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true) }
        else {
          guard let args = call.arguments as? [String: String], let path = args["path"], let name = args["name"], !name.isEmpty,
            !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { throw NSError(domain:"ThorFiles",code:4) }
          let source = URL(fileURLWithPath:path).standardizedFileURL
          guard source.path.hasPrefix(transferDirectory.standardizedFileURL.path + "/") else { throw NSError(domain:"ThorFiles",code:5) }
          // A private export directory gives Files the original name without overwriting cached downloads.
          let export = transferDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true)
          try FileManager.default.createDirectory(at: export, withIntermediateDirectories:true)
          let destination = export.appendingPathComponent(name)
          try FileManager.default.moveItem(at:source,to:destination)
          picker = UIDocumentPickerViewController(forExporting:[destination],asCopy:true)
        }
        fileMode = call.method; fileResult = result; picker.delegate = self; picker.allowsMultipleSelection = false
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard var presenter = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController ?? window?.rootViewController else { fileResult = nil; throw NSError(domain:"ThorFiles",code:6) }
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(picker, animated:true)
      default: result(FlutterMethodNotImplemented)
      }
    } catch { let failure = error as NSError; result(FlutterError(code:"files",message: failure.domain == "ThorFiles" && failure.code == 6 ? "Keep Thor Companion open to use the Files picker." : "Could not open the selected file or Files picker. Check available space and file access.",details:["domain":failure.domain,"code":failure.code])) }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { fileResult?(nil); fileResult = nil; cleanupExports() }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = fileResult else { return }; fileResult = nil
    if fileMode == "saveFile" { result(true); cleanupExports(); return }
    guard let url = urls.first else { result(nil); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      do {
        let destination = self.transferDirectory.appendingPathComponent("upload-" + UUID().uuidString)
        try FileManager.default.copyItem(at:url,to:destination)
        let size = try FileManager.default.attributesOfItem(atPath:destination.path)[.size] as? NSNumber
        DispatchQueue.main.async { result(["path":destination.path,"name":url.lastPathComponent,"size":size?.int64Value ?? 0]) }
      } catch { DispatchQueue.main.async { result(FlutterError(code:"files_pick",message:"Could not copy this file. Check available space and download it from iCloud first if needed.",details:nil)) } }
    }
  }
  private func cleanupExports() { if let urls = try? FileManager.default.contentsOfDirectory(at:transferDirectory,includingPropertiesForKeys:[.isDirectoryKey]) { for url in urls { if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true { try? FileManager.default.removeItem(at:url) } } } }
}

extension AppDelegate {
  private static func recordingError(_ error: Error) -> String {
    let value = error as NSError
    return "\(value.domain) \(value.code)" + ((value.userInfo[NSUnderlyingErrorKey] as? NSError).map { " / " + recordingError($0) } ?? "")
  }
  private func saveRecording(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let paths = args["paths"] as? [String],
          let offsets = args["offsets"] as? [NSNumber], let screen = args["screen"] as? String, let fps = args["fps"] as? Int, [30, 60].contains(fps),
          ["top", "bottom", "both"].contains(screen), paths.count == (screen == "both" ? 2 : 1),
          paths.count == offsets.count else {
      result(FlutterError(code: "recording", message: "Invalid recording files.", details: nil)); return
    }
    let sources = paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL }
    let root = transferDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    guard sources.allSatisfy({ url in
      guard url.path.hasPrefix(root), url.pathExtension == "mp4",
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true, let size = values.fileSize else { return false }
      return size >= 128 && size <= 512 * 1024 * 1024
    }) else { result(FlutterError(code: "recording", message: "Recording cache is unavailable. Download again.", details: nil)); return }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
      guard authorization == .authorized || authorization == .limited else {
        DispatchQueue.main.async { result(FlutterError(code: "photos_permission", message: "Allow Thor Companion to add captures in iPhone Settings, then tap Save to Photos.", details: nil)) }; return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        ThorVideoComposer.compose(sources, offsets: offsets.map { $0.doubleValue }, fps: fps, directory: self.transferDirectory) { exported in
          switch exported {
          case .failure(let error): DispatchQueue.main.async { result(FlutterError(code: "recording_export", message: "Could not combine screens. The Thor copy is kept; try Save to Photos again.", details: Self.recordingError(error))) }
          case .success(let output):
            PHPhotoLibrary.shared().performChanges({
              let asset = PHAssetCreationRequest.forAsset()
              let options = PHAssetResourceCreationOptions()
              options.originalFilename = "Thor-\(screen)-\(Int(Date().timeIntervalSince1970)).mp4"
              asset.addResource(with: .video, fileURL: output, options: options)
            }) { success, error in
              if !sources.contains(output) { try? FileManager.default.removeItem(at: output) }
              DispatchQueue.main.async {
                if success { result(nil) }
                else { result(FlutterError(code: "recording_save", message: "Could not add the recording to Photos. The Thor copy is kept; try Save to Photos again.", details: error.map { Self.recordingError($0) })) }
              }
            }
          }
        }
      }
    }
  }
}
