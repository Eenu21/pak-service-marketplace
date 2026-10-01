# Pak Service Marketplace (Flutter iOS + Android)

Production-grade service marketplace architecture for Pakistan with:

- Clean Flutter codebase (Riverpod + GoRouter + null safety)
- Premium UI baseline (modern typography, spacing, micro-animations)
- Mandatory Terms/Privacy acceptance before registration
- Terms acceptance storage with timestamp, IP/device metadata, and versioning
- Real-time job flows (post, nearby discovery, bids, acceptance, status updates)
- Privacy-aware address handling (exact address shown only after assignment)
- Payment logic with 7.5% fee split (online and cash recorded)
- Real-time chat + notifications + full audit log model
- Persistent customer/professional profiles and per-session login/logout activity records
- Pro dashboard (today/month/lifetime, cash vs online, fees, ratings)
- Admin dashboard (users/pros, verification, commission, analytics, audit)
- Firebase Auth + Firestore backend wiring with local fallback

## Tech Stack

- Flutter 3.41+
- State management: `flutter_riverpod`
- Navigation: `go_router`
- Backend: Firebase Auth + Cloud Firestore (with local in-memory fallback)
- Maps/location: `google_maps_flutter`, `geolocator`, `permission_handler`
- UI polish: `google_fonts`, `flutter_animate`

## Project Structure

- `lib/src/core`: config, theme, routing, localization, platform services
- `lib/src/domain`: core entities/enums (jobs, bids, payments, users, audit)
- `lib/src/data/repositories`: repository contracts + local/supabase implementations
- `lib/src/presentation`: screens + Riverpod controllers
- `backend/supabase/migrations`: SQL schema and RLS/audit setup

## Environment Configuration

Use `--dart-define` (or CI secrets):

- `FIREBASE_API_KEY`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_APP_ID`
- `FIREBASE_MEASUREMENT_ID`
- `GOOGLE_MAPS_API_KEY`
- `TERMS_VERSION` (default: `v1.0`)
- `PRIVACY_VERSION` (default: `v1.0`)
- `PLATFORM_FEE_RATE` (default: `0.075`)
- `BOOTSTRAP_ADMIN_EMAILS` (comma-separated allowlist, default empty)

Example:

```bash
flutter run \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY \
  --dart-define=FIREBASE_AUTH_DOMAIN=YOUR_PROJECT.firebaseapp.com \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID \
  --dart-define=FIREBASE_STORAGE_BUCKET=YOUR_PROJECT.appspot.com \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID \
  --dart-define=FIREBASE_APP_ID=YOUR_WEB_APP_ID \
  --dart-define=FIREBASE_MEASUREMENT_ID=YOUR_MEASUREMENT_ID \
  --dart-define=GOOGLE_MAPS_API_KEY=YOUR_MAPS_KEY \
  --dart-define=TERMS_VERSION=v1.0 \
  --dart-define=PRIVACY_VERSION=v1.0 \
  --dart-define=PLATFORM_FEE_RATE=0.075 \
  --dart-define=BOOTSTRAP_ADMIN_EMAILS=admin@yourdomain.com
```

## Android/iOS Maps Setup

- Android uses manifest placeholder `GOOGLE_MAPS_API_KEY` in `android/app/build.gradle.kts`
- iOS reads `GMSApiKey` from `ios/Runner/Info.plist` via `AppDelegate.swift`
- Configure location usage strings in iOS `Info.plist` (already included)

## Firebase Setup

Enable these Firebase products for your project:

- Authentication with Email/Password
- Cloud Firestore in production mode

Main collections used by the app:

- `profiles`
- `jobs`
- `bids`
- `payments`
- `chat_messages`
- `notifications`
- `audit_logs`
- `reports`
- `app_settings`

Notes:

- Web can initialize directly from the Firebase web config.
- Android still needs `android/app/google-services.json` from the Firebase console.
- iOS still needs `ios/Runner/GoogleService-Info.plist` from the Firebase console.
- If native Firebase is not configured, the app falls back to the local repository on non-web platforms.

## Demo Accounts (Local Repository Mode)

- Customer: `user@pakservice.pk / User12345!`
- Professional: `pro@pakservice.pk / Pro12345!`
- Admin: `admin@pakservice.pk / Admin123!`

## Notes

- The checked-in web Firebase config matches the shared project config and can be overridden with `--dart-define`.
- Without Firebase initialization, app runs in fully functional local mode for fast development.
- Online payout integration (JazzCash/Easypaisa provider APIs) should be wired to production gateway webhooks per your merchant account setup.
- Keep `BOOTSTRAP_ADMIN_EMAILS` empty in normal production operation and use it only for controlled first-time admin bootstrap.
