// Firebase configuration options.
//
// On Android/iOS the app initializes Firebase from the native config files
// (google-services.json / GoogleService-Info.plist) via a no-arg
// Firebase.initializeApp(). The web platform has no such file, so it must be
// given explicit options — that is what [DefaultFirebaseOptions.web] provides.
//
// NOTE: `appId` below is a placeholder in web format derived from the project's
// Android app id. Auth/Firestore work without a registered web app, but Firebase
// Cloud Messaging (push) and Analytics on web require a real Web App registered
// in the Firebase console (project: ehrms-929bb). Run `flutterfire configure`
// or copy the web app's config here to enable those.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCNLUlI8TYeVA9Ind4YGZB79YiVj8peguQ',
    appId: '1:761328490721:web:3f05090eb421f840c2ffa0',
    messagingSenderId: '761328490721',
    projectId: 'ehrms-929bb',
    authDomain: 'ehrms-929bb.firebaseapp.com',
    storageBucket: 'ehrms-929bb.firebasestorage.app',
  );
}
