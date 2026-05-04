# Almarmous Orders

A modern bilingual Flutter app for iOS and Android order tracking. It imports delivery labels with OCR, extracts order details, stores orders locally, tracks statuses, and shows dashboard/report summaries.

## Features

- Arabic and English UI with RTL/LTR switching.
- OCR import from camera or gallery using Google ML Kit.
- Extracts tracking number, recipient phone, city, area, and COD amount from shipping labels.
- Order statuses: sent, delivered, returned.
- Dashboard counters and COD totals.
- Searchable order list with status chips.
- Quick dashboard actions for camera scan, gallery import, and manual order entry.
- One-tap status changes from each order card.
- Barcode scanning for tracking numbers, with OCR as fallback.
- Duplicate tracking-number warning that opens the existing order.
- OCR review with the label image above editable extracted fields.
- WhatsApp action on every order with a recipient phone number.
- Order timeline/history for creation and status changes.
- Date-filtered reports with PDF and Excel export/share.
- Local role selection for admin, staff, and driver permissions.
- Almarmous Arabic-first branding based on almarmous.ae.
- Reports screen with status totals and recent activity.
- Local persistence with `shared_preferences`.

## Run

Flutter is not installed on this machine right now. After installing the latest stable Flutter SDK:

```sh
flutter create . --platforms=ios,android
flutter pub get
flutter run
```

For Android 16, use compile/target SDK 36 in the generated Android Gradle config when your installed Flutter/Android SDK supports it.

This project uses current package versions that require a recent Flutter SDK with Dart 3.10 or newer.

For camera/gallery OCR, add platform permissions after generating native folders:

Android `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

iOS `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan shipping labels to extract order details.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose shipping label photos to extract order details.</string>
```
