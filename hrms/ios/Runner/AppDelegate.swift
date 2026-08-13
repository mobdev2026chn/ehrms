import Flutter
import UIKit
import GoogleMaps
import background_location_tracker

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyBcoj_g5hxrsv3mEJCVF1Uev_JZRcFO0F8")
    GeneratedPluginRegistrant.register(with: self)
    BackgroundLocationTrackerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
