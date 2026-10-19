# PETORA – Flutter Android app

Buyer + seller app for the PETORA marketplace (Material 3, Riverpod, Dio, GoRouter). It talks to the same
`/api/v1` backend as the website; the contract is `../docs/openapi.yaml`, design tokens are in
`../docs/DESIGN_SYSTEM.md` (implemented in `lib/ui/tokens.dart`).

## Layout
```
lib/
  core/        config (dart-define), AppException mapping, Dio ApiClient (single-flight refresh), token store, formatting
  models/      plain JSON models (money is always integer minor units)
  data/        repositories (auth, catalogue, buyer, seller, billing, account) + media picker abstraction
  state/       Riverpod providers (auth, paged lists, data, theme, location)
  ui/          tokens, light/dark theme, reusable components (lib/ui/widgets)
  features/    auth, setup, shell (buyer/seller/staff), home, search, pet, favourites, enquiries, billing, account, seller
  router.dart  GoRouter with role-aware redirects (redirectFor is unit tested)
test/          unit, widget and responsive tests + a fake backend (Dio adapter); live_smoke_test.dart is opt-in
```

## Configuration
Set with `--dart-define`:

| define | values | default |
|---|---|---|
| `APP_ENV` | `dev` · `staging` · `prod` | `dev` |
| `API_BASE_URL` | full URL incl. `/api/v1` | dev `http://10.0.2.2:8080/api/v1` (emulator → host), staging `https://staging.petora.in/api/v1`, prod `https://petora.in/api/v1` |

Release builds **throw at start-up** if the base URL is not `https` (or is localhost/10.0.2.2). Cleartext HTTP is
only permitted by the debug-only `network_security_config` for `10.0.2.2`/`localhost`.

```bash
flutter run --dart-define=APP_ENV=dev                                   # emulator against local backend
flutter run --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://192.168.1.20:8080/api/v1   # real device on LAN
flutter build apk --release --dart-define=APP_ENV=prod                  # production APK
flutter build appbundle --release --dart-define=APP_ENV=prod            # Play Store bundle
```

## Android build prerequisites
Flutter 3.47+/Dart 3.13+, JDK 17+, the Android SDK (platform + build-tools) with `ANDROID_HOME` set and licences
accepted (`flutter doctor --android-licenses`). `applicationId` is `in.petora.app`, `minSdk` 23.

Release signing: create `android/key.properties` (git-ignored) with `storeFile`, `storePassword`, `keyAlias`,
`keyPassword`. Without it release builds fall back to the debug key – never ship that.

**Payments:** `razorpay_flutter` is used when the backend reports `provider: razorpay` (needs the merchant key
configured server-side). With `provider: testmode` the app shows a *TEST MODE – no real charge* banner and
simulate buttons. The app never shows success from the SDK callback: it always calls `POST /payments/{id}/verify`
and polls `GET /payments/{id}`.

## Tests
```bash
flutter analyze
flutter test                                   # offline suite (fake backend)
SMOKE_API_URL=http://localhost:8080/api/v1 SMOKE_LOG=/path/to/worker.log \
  flutter test test/live_smoke_test.dart       # optional: runs against a live backend
```
The smoke test registers a throw-away buyer, reads the verification code from the worker's `DEV EMAIL` log line,
and walks locked → test-mode payment → unlock → enquiry → seller reply, plus a refresh-rotation check. It is
subject to the backend's per-IP register rate limit.

## Known limitations
* Android APK has not been built in CI/this environment (no Android SDK available); only `flutter analyze` and
  `flutter test` were run. Native plugin wiring (razorpay, geolocator, secure storage) is therefore untested on a device.
* Push notifications: the notification explainer stores the preference only; there is no FCM integration or push
  backend yet, so no OS permission prompt is requested and `POST_NOTIFICATIONS` is not declared.
* Enquiry threads refresh by polling every 15 s while open (no websocket).
* Staff accounts are shown a "use the web admin portal" screen.
* Fonts: Inter is bundled (`assets/fonts`, SIL OFL). No stock photos are bundled; listings without photos show a
  category-icon placeholder.
