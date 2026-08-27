import FirebaseMessaging
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

  /// State the APNs environment rather than letting FCM infer it.
  ///
  /// A debug build is issued a token by the APNs *sandbox*; TestFlight and the
  /// App Store are issued a production one. They are different tokens on
  /// different endpoints, and sending to the wrong one fails quietly. FCM reads
  /// `aps-environment` from the entitlement to work this out, and occasionally
  /// gets it wrong — at which point every push simply stops arriving, with no
  /// error anywhere. Being explicit costs four lines.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    #if DEBUG
      Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
    #else
      Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
    #endif
    super.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
