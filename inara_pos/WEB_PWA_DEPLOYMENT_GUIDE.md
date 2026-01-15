# Flutter Web PWA Deployment Guide

Complete guide to convert your Flutter mobile app to a Progressive Web App (PWA) with offline support and Firebase Firestore integration.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Firebase Setup](#firebase-setup)
3. [Project Configuration](#project-configuration)
4. [Building the Web App](#building-the-web-app)
5. [PWA Configuration](#pwa-configuration)
6. [Deployment Options](#deployment-options)
7. [Testing on iPhone and Android](#testing-on-iphone-and-android)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### 1. Install Flutter Web Support

```bash
# Check Flutter version (should be 3.0+)
flutter --version

# Enable web support
flutter config --enable-web

# Verify web support
flutter devices
# You should see "Chrome" in the list
```

### 2. Install Firebase CLI

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Login to Firebase
firebase login

# Verify installation
firebase --version
```

### 3. Required Packages

All required packages are already in `pubspec.yaml`. The key packages for web support:

- `firebase_core: ^2.24.2` - Firebase initialization
- `cloud_firestore: ^4.13.6` - Firestore database (with offline persistence)
- `shared_preferences: ^2.2.2` - Local storage (works on web)
- `provider: ^6.1.1` - State management

**Note:** `sqflite` is automatically replaced with Firestore on web via `UnifiedDatabaseProvider`.

---

## Firebase Setup

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Enter project name: `inara-pos` (or your preferred name)
4. Disable Google Analytics (optional)
5. Click "Create project"

### Step 2: Enable Firestore Database

1. In Firebase Console, go to **Firestore Database**
2. Click "Create database"
3. Choose **Start in test mode** (we'll update rules later)
4. Select a location (choose closest to your users)
5. Click "Enable"

### Step 3: Configure Firestore Security Rules

1. Go to **Firestore Database** > **Rules**
2. Replace with these rules (adjust as needed):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write access to all documents (adjust for production)
    match /{document=**} {
      allow read, write: if request.auth != null || 
        request.auth == null; // Allow unauthenticated for now
    }
    
    // For production, use proper authentication:
    // match /users/{userId} {
    //   allow read, write: if request.auth != null && request.auth.uid == userId;
    // }
  }
}
```

3. Click "Publish"

### Step 4: Get Firebase Configuration

1. Go to **Project Settings** (gear icon)
2. Scroll down to "Your apps"
3. Click the **Web** icon (`</>`)
4. Register app with nickname: "InaraPOS Web"
5. Copy the Firebase configuration object

### Step 5: Add Firebase Config to Flutter

Create `lib/firebase_options.dart` (or update existing):

```dart
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
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  // Add android and ios if needed
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
  );
}
```

**Or use Firebase CLI to generate:**

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase for your project
flutterfire configure
```

This will automatically generate `firebase_options.dart` with correct configuration.

### Step 6: Update main.dart to Use Firebase Options

Update `lib/main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  
  // ... rest of the code
}
```

---

## Project Configuration

### 1. Update pubspec.yaml

The `pubspec.yaml` is already configured correctly. Key points:

- ✅ `firebase_core` and `cloud_firestore` are included
- ✅ `sqflite` will only be used on mobile (not web)
- ✅ All other packages support web

### 2. Verify Web Assets

Ensure these files exist in `web/` directory:

- `index.html` ✅ (already updated)
- `manifest.json` ✅ (already updated)
- `icons/Icon-192.png` (create if missing)
- `icons/Icon-512.png` (create if missing)
- `favicon.png` (create if missing)

### 3. Create PWA Icons

If icons are missing, create them:

```bash
# Create icons directory
mkdir -p web/icons

# You can use online tools like:
# - https://realfavicongenerator.net/
# - https://www.pwabuilder.com/imageGenerator
# Or use your logo image (assets/images/logo.jpeg)

# Required sizes:
# - 192x192 (Icon-192.png)
# - 512x512 (Icon-512.png)
# - Maskable versions (Icon-maskable-192.png, Icon-maskable-512.png)
```

---

## Building the Web App

### Step 1: Build for Web

```bash
# Navigate to project directory
cd inara_pos

# Get dependencies
flutter pub get

# Build for web (release mode)
flutter build web --release

# The build output will be in: build/web/
```

### Step 2: Test Locally

```bash
# Run web app locally
flutter run -d chrome

# Or serve the build folder
cd build/web
python -m http.server 8000
# Then open http://localhost:8000 in browser
```

### Step 3: Verify Build

Check that `build/web/` contains:

- `index.html`
- `manifest.json`
- `main.dart.js` (compiled Dart code)
- `flutter.js`
- `icons/` folder with all icons
- `assets/` folder with images

---

## PWA Configuration

### 1. Service Worker (Auto-generated)

Flutter automatically generates a service worker for PWA functionality. It's included in the build output.

### 2. Manifest.json

Already configured in `web/manifest.json` with:

- ✅ App name and description
- ✅ Icons for all sizes
- ✅ Standalone display mode
- ✅ Theme colors
- ✅ Start URL

### 3. Offline Support

Firestore offline persistence is enabled in `FirestoreDatabaseProvider`:

```dart
_firestore!.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

This means:
- ✅ Data is cached locally
- ✅ App works offline
- ✅ Changes sync automatically when online

---

## Deployment Options

### Option 1: Firebase Hosting (Recommended)

**Pros:** Free, easy, integrates with Firebase

```bash
# Initialize Firebase in your project
cd inara_pos
firebase init hosting

# Select:
# - Use existing project: Yes
# - Public directory: build/web
# - Single-page app: Yes
# - Set up automatic builds: No (for now)

# Deploy
flutter build web --release
firebase deploy --only hosting

# Your app will be live at:
# https://YOUR_PROJECT_ID.web.app
# or
# https://YOUR_PROJECT_ID.firebaseapp.com
```

### Option 2: Netlify

**Pros:** Free, automatic deployments from Git

1. Push code to GitHub/GitLab
2. Go to [Netlify](https://www.netlify.com/)
3. Click "New site from Git"
4. Connect repository
5. Build settings:
   - Build command: `flutter build web --release`
   - Publish directory: `build/web`
6. Deploy!

### Option 3: Vercel

**Pros:** Free, fast CDN

```bash
# Install Vercel CLI
npm i -g vercel

# Deploy
cd inara_pos
flutter build web --release
cd build/web
vercel

# Follow prompts
```

### Option 4: Any Static Hosting

You can deploy `build/web/` folder to:

- GitHub Pages
- AWS S3 + CloudFront
- Azure Static Web Apps
- Any web server (Apache, Nginx)

Just upload the contents of `build/web/` to your hosting provider.

---

## Testing on iPhone and Android

### iPhone (Safari)

1. **Deploy your app** to a public URL (Firebase Hosting, Netlify, etc.)

2. **Open Safari** on iPhone

3. **Navigate** to your app URL

4. **Add to Home Screen:**
   - Tap the Share button (square with arrow)
   - Scroll down and tap "Add to Home Screen"
   - Customize name if needed
   - Tap "Add"

5. **Launch PWA:**
   - Tap the icon on home screen
   - App opens in standalone mode (no browser UI)

6. **Test Offline:**
   - Enable Airplane Mode
   - App should still work with cached data
   - Changes will sync when back online

### Android (Chrome)

1. **Deploy your app** to a public URL

2. **Open Chrome** on Android

3. **Navigate** to your app URL

4. **Install PWA:**
   - Chrome will show an "Install" banner automatically
   - Or tap menu (3 dots) > "Add to Home screen" or "Install app"

5. **Launch PWA:**
   - Tap the icon on home screen
   - App opens in standalone mode

6. **Test Offline:**
   - Enable Airplane Mode
   - App should still work with cached data

### Testing Checklist

- [ ] App loads correctly
- [ ] Login works
- [ ] Data persists (Firestore)
- [ ] Works offline (cached data)
- [ ] Changes sync when back online
- [ ] Icons display correctly
- [ ] Standalone mode works (no browser UI)
- [ ] Responsive design works on mobile

---

## Troubleshooting

### Issue: Firebase not initializing

**Solution:**
- Check `firebase_options.dart` has correct values
- Ensure Firebase project is created
- Verify Firestore is enabled

### Issue: "Service worker registration failed"

**Solution:**
- Ensure app is served over HTTPS (required for PWA)
- Check browser console for errors
- Verify `manifest.json` is accessible

### Issue: Offline data not working

**Solution:**
- Check Firestore offline persistence is enabled
- Verify network tab shows cached responses
- Clear browser cache and retry

### Issue: Icons not showing

**Solution:**
- Verify icon files exist in `web/icons/`
- Check `manifest.json` paths are correct
- Ensure icons are PNG format
- Clear browser cache

### Issue: "Add to Home Screen" not appearing

**Solution:**
- App must be served over HTTPS
- `manifest.json` must be valid
- App must be visited at least once
- For iOS: Use Safari (not Chrome)

### Issue: Build fails

**Solution:**
```bash
# Clean build
flutter clean
flutter pub get

# Try building again
flutter build web --release
```

### Issue: Database queries not working on web

**Solution:**
- Verify `UnifiedDatabaseProvider` is being used
- Check Firestore security rules allow access
- Ensure Firebase is initialized before database calls

---

## Plugin Compatibility

### ✅ Web Compatible

- `firebase_core` - ✅ Works on web
- `cloud_firestore` - ✅ Works on web with offline persistence
- `shared_preferences` - ✅ Works on web (uses localStorage)
- `provider` - ✅ Works on web
- `intl` - ✅ Works on web
- `fl_chart` - ✅ Works on web
- `qr_flutter` - ✅ Works on web
- `image_picker` - ✅ Works on web (camera/file picker)
- `file_picker` - ✅ Works on web
- `share_plus` - ✅ Works on web (Web Share API)
- `connectivity_plus` - ✅ Works on web
- `dio` - ✅ Works on web

### ❌ Not Web Compatible (Handled)

- `sqflite` - ❌ Replaced with Firestore on web via `UnifiedDatabaseProvider`
- `path_provider` - ⚠️ Limited web support, but not used in web code paths
- `sqflite_common_ffi` - ❌ Not needed on web

---

## Production Checklist

Before deploying to production:

- [ ] Update Firestore security rules (use authentication)
- [ ] Set up Firebase Authentication (if needed)
- [ ] Configure custom domain (optional)
- [ ] Test on multiple devices (iPhone, Android, Desktop)
- [ ] Test offline functionality
- [ ] Verify all features work
- [ ] Set up analytics (optional)
- [ ] Configure error tracking (optional)
- [ ] Test performance
- [ ] Optimize images and assets
- [ ] Enable compression on hosting

---

## Next Steps

1. **Set up Firebase Authentication** (if you want user accounts)
2. **Configure Firestore security rules** for production
3. **Set up custom domain** for your PWA
4. **Add analytics** to track usage
5. **Optimize performance** (code splitting, lazy loading)

---

## Support

For issues or questions:

1. Check Firebase Console for errors
2. Check browser console (F12) for JavaScript errors
3. Check Flutter logs: `flutter run -d chrome -v`
4. Review Firestore security rules
5. Verify Firebase configuration

---

## Summary

Your Flutter app is now:

✅ **Web-compatible** - Works in browsers  
✅ **PWA-ready** - Can be installed on home screen  
✅ **Offline-capable** - Works without internet  
✅ **Firestore-integrated** - Real-time database with sync  
✅ **Cross-platform** - Works on iPhone, Android, Desktop  

The app automatically uses:
- **SQLite** on mobile (Android/iOS)
- **Firestore** on web (with offline persistence)

All existing features should work seamlessly across platforms!
