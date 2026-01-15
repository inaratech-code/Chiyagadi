// Firebase configuration for ChiyaGadi POS
// Generated from Firebase Console web app configuration

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAE1vchX5X70H_Ec4UIk_DLLOjx51W3kyc',
    appId: '1:905761269162:web:bbac95e09878d7006d37d3',
    messagingSenderId: '905761269162',
    projectId: 'chiyagadi-cf302',
    authDomain: 'chiyagadi-cf302.firebaseapp.com',
    storageBucket: 'chiyagadi-cf302.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAE1vchX5X70H_Ec4UIk_DLLOjx51W3kyc',
    appId: '1:905761269162:android:YOUR_ANDROID_APP_ID',
    messagingSenderId: '905761269162',
    projectId: 'chiyagadi-cf302',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAE1vchX5X70H_Ec4UIk_DLLOjx51W3kyc',
    appId: '1:905761269162:ios:YOUR_IOS_APP_ID',
    messagingSenderId: '905761269162',
    projectId: 'chiyagadi-cf302',
    iosBundleId: 'com.inaratech.inarapos',
  );
}
