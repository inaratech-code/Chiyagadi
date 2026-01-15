# Quick Start: Deploy Flutter Web PWA

## Step 1: Setup Firebase (5 minutes)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project: `inara-pos`
3. Enable **Firestore Database** (Start in test mode)
4. Get your Firebase config:
   - Project Settings > Your apps > Add Web app
   - Copy the config values

## Step 2: Configure Firebase in Flutter

**Option A: Using FlutterFire CLI (Recommended)**

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure

# Select your Firebase project
# Select platforms: web, android, ios
```

This automatically generates `lib/firebase_options.dart`.

**Option B: Manual Configuration**

1. Copy `lib/firebase_options_template.dart` to `lib/firebase_options.dart`
2. Replace `YOUR_*` values with your Firebase config
3. Update `lib/main.dart` to import and use it:

```dart
import 'firebase_options.dart';

// In main():
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

## Step 3: Build Web App

```bash
# Get dependencies
flutter pub get

# Build for web
flutter build web --release
```

Output: `build/web/` folder

## Step 4: Deploy (Choose one)

### Firebase Hosting (Easiest)

```bash
# Initialize Firebase Hosting
firebase init hosting

# Select:
# - Public directory: build/web
# - Single-page app: Yes

# Deploy
firebase deploy --only hosting
```

Your app: `https://YOUR_PROJECT_ID.web.app`

### Netlify (Free, Git-based)

1. Push code to GitHub
2. Go to [Netlify](https://www.netlify.com/)
3. New site from Git
4. Build command: `flutter build web --release`
5. Publish directory: `build/web`

### Vercel (Recommended for your setup)

**Important**: Vercel does not include Flutter by default, so you must either:

- Build web using CI (GitHub Actions) and deploy the built output, or
- Use a Vercel build environment that has Flutter installed.

**If your Vercel project root is `inara_pos/`:**

- Root Directory: `inara_pos`
- Build Command: `flutter build web --release`
- Output Directory: `build/web`

**SPA routing fix**: this repo includes `vercel.json` (and `inara_pos/vercel.json`) to rewrite all routes to `index.html`.

### Any Web Server

Just upload the contents of `build/web/` to your hosting provider.

## Step 5: Test on Mobile

### iPhone:
1. Open Safari
2. Go to your app URL
3. Share > Add to Home Screen
4. Launch from home screen

### Android:
1. Open Chrome
2. Go to your app URL
3. Menu > Install app (or Add to Home screen)
4. Launch from home screen

## Troubleshooting

**Firebase not working?**
- Check `firebase_options.dart` has correct values
- Verify Firestore is enabled in Firebase Console
- Check browser console for errors

**PWA not installing?**
- Must be served over HTTPS
- Check `manifest.json` is valid
- Verify icons exist in `web/icons/`

**Offline not working?**
- Firestore offline persistence is enabled automatically
- First visit must be online to cache data
- Check browser cache settings

## What's Different on Web?

- ✅ **Database**: Uses Firestore (instead of SQLite)
- ✅ **Offline**: Firestore caches data automatically
- ✅ **Sync**: Changes sync when online
- ✅ **All Features**: Everything works the same!

The app automatically detects the platform and uses the right database.
