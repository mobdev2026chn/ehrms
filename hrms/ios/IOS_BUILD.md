# iOS Build Guide — EktaHR (`hrms`)

iOS builds **only run on macOS** with Xcode. Do these steps on a Mac after copying
the repo over. Bundle ID is `io.askeva.ektahr`; Firebase project is `ehrms-929bb`.

## 0. One-time Mac setup
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo gem install cocoapods           # or: brew install cocoapods
flutter doctor                       # Xcode + CocoaPods rows must be green
```

## 1. Clean the Windows-built artifacts
From `ehrms/hrms`:
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates *.g.dart
```

## 2. Add the Firebase iOS config (REQUIRED — app crashes without it)
The app calls a no-arg `Firebase.initializeApp()` on iOS, so it needs a native plist.
1. Firebase console → project `ehrms-929bb` → Add app → iOS, bundle ID `io.askeva.ektahr`.
2. Download `GoogleService-Info.plist`.
3. Save it as `ios/Runner/GoogleService-Info.plist` and add it to the **Runner** target
   in Xcode ("Copy items if needed"). See `ios/Runner/GoogleService-Info.plist.template`.

## 3. Enable Google Sign-In URL scheme
In `ios/Runner/Info.plist` there's a commented `CFBundleURLTypes` block. Uncomment it and
paste the `REVERSED_CLIENT_ID` from the plist above. (Skip only if Google sign-in is unused.)

## 4. Pods
```bash
cd ios
pod install        # first run is slow (Firebase, ML Kit, camerawesome). Then:
cd ..
open ios/Runner.xcworkspace      # open the WORKSPACE, not .xcodeproj
```
A `Podfile` is already committed here, pinned to iOS 15 with permission_handler macros.

## 5. Signing (needs a paid Apple Developer account, $99/yr)
Xcode → **Runner target → Signing & Capabilities**:
- Select your **Team**, enable **Automatically manage signing**.
- For push: add **Push Notifications** capability and **Background Modes → Remote
  notifications** (Info.plist already declares the background modes), and upload an
  **APNs auth key** to Firebase Cloud Messaging settings.

## 6. Run / build
```bash
flutter devices
flutter run                       # debug on a connected iPhone / simulator
flutter run --release             # release on device (needs signing)
flutter build ipa                 # produces build/ios/ipa/*.ipa for TestFlight / App Store
```
Or archive from Xcode: **Product → Archive → Distribute App**.

## Notes specific to this app
- **Real device required** for camera, face enrollment/punch (`camerawesome`,
  `google_mlkit_face_detection`) — the iOS Simulator has no camera.
- `background_location_tracker` is vendored at `packages/` via a `dependency_override`;
  make sure that folder came across or `flutter pub get` fails.
- Default API base is production (`https://ehrms.askeva.net/api`) — no flags needed for a
  prod build. The Google Maps iOS key is already set in `Runner/AppDelegate.swift`.
