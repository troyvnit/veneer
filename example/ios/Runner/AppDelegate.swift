import Flutter
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

    // Launch-argument config for scripted measurement runs, e.g.
    //   xcrun simctl launch <udid> <bundle> -VENEER_TRANSPORT ffi -VENEER_MEASURE 1
    // (`-key value` arguments land in UserDefaults' argument domain.)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ExampleLaunchConfig") {
      let channel = FlutterMethodChannel(name: "example/launch_config", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { _, result in
        let defaults = UserDefaults.standard
        result([
          "transport": defaults.string(forKey: "VENEER_TRANSPORT"),
          "measure": defaults.string(forKey: "VENEER_MEASURE"),
        ])
      }
    }
  }
}
