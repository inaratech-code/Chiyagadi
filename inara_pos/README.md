# InaraPOS – Single Café Edition

**Offline-first POS system for small cafés in Nepal**

Built by **Inara Tech**

## Features

- ✅ **Offline-first**: Works completely offline, syncs when online
- ✅ **Android Native App** (APK installation)
- ✅ **iOS PWA** (Progressive Web App)
- ✅ **SQLite Primary Database** (local storage)
- ✅ **Firestore Backup** (optional cloud sync)
- ✅ **Thermal Printing** (Bluetooth & Network)
- ✅ **Table Management**
- ✅ **KOT System**
- ✅ **Inventory Management**
- ✅ **Purchase & Sales**
- ✅ **Daily Reports**

## Platform Support

- **Android**: Flutter native APK (manual installation)
- **iOS**: Flutter Web PWA (install via Safari)

## Architecture

- **Mobile App**: Flutter
- **Local Database**: SQLite (primary)
- **Cloud Database**: Firebase Firestore (backup/sync only)
- **Printing**: ESC/POS thermal printers (Bluetooth + Network)

## Installation

### Android (APK)

1. Build APK: `flutter build apk --release`
2. Transfer APK to Android device
3. Enable "Install from Unknown Sources"
4. Install APK

### iOS (PWA)

1. Build Web: `flutter build web --release`
2. Deploy to web server
3. Open in Safari on iOS
4. Share → Add to Home Screen

## Initial Setup

1. **First Launch**: Set admin PIN (4-6 digits)
2. **Firebase Setup** (Optional): Add `google-services.json` (Android) and configure Firebase
3. **Printer Setup**: Configure thermal printer (Bluetooth or Network)
4. **Settings**: Configure café name, address, tax rate, etc.

## Database Schema

See `lib/database/schema.sql` for complete SQLite schema.

## Sync Strategy

- **Primary**: SQLite (local, always available)
- **Sync**: Firestore (background sync when online)
- **Policy**: SQLite always wins, Firestore never blocks operations

## Security

- PIN-based authentication
- Role-based access (Admin/Cashier)
- Firestore security rules (owner-only write)
- Local data encryption (recommended for production)

## License

Proprietary - Inara Tech

## Support

For support, contact Inara Tech.
