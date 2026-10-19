# 🟢 G-Lanterns 3D

**An immersive Green Lantern Power Battery Simulator built with Flutter.**

G-Lanterns 3D transforms your phone into an interactive Green Lantern Power Battery, bringing the power of the Green Lantern Corps to life through 3D lantern models, voice-activated charging, cinematic sound effects, custom haptic feedback, and an interactive comic-book introduction.

> *“In brightest day, in blackest night...”*

## ✨ Features

- **🎙️ Voice-Activated Charging** — Recite the Green Lantern oath of Hal Jordan or John Stewart to charge the battery. Real-time speech recognition and karaoke-style text highlighting provide an immersive charging experience.
- **🟢 Interactive 3D Lanterns** — Explore high-quality `.glb` models of Hal Jordan's and John Stewart's Power Batteries, featuring automatic rotation and touch-responsive animations.
- **📳 Custom Haptic Feedback** — Native Kotlin integration delivers tactile effects, including micro-ticks, magnetic lock-ons, and powerful energy-blast vibrations.
- **🔋 Dynamic Battery Drain** — Battery charge depletes according to elapsed real-world time, with calculations that account for time spent outside the app.
- **🔔 Low-Battery Notifications** — Receive local notifications at 20%, 15%, 10%, 5%, and 0% charge.
- **👊 Acoustic Knock Charge** — Use a double-tap or knock on a surface to trigger an emergency charge that restores 5% battery power.
- **📖 Cinematic Comic-Book Intro** — Experience an interactive, multi-page origin story featuring voiceovers, sound effects, and user choices.
- **🔊 Custom Audio Handling** — Native Android audio management helps suppress speech-recognition system sounds while preserving the app's sound effects.

## 🛠️ Tech Stack

| Technology | Purpose |
|---|---|
| Flutter & Dart | Cross-platform app development |
| Kotlin | Native Android integration |
| `model_viewer_plus` | Interactive 3D model rendering |
| `webview_flutter` | WebView support |
| `speech_to_text` | Voice recognition |
| `audioplayers` | Sound effects and audio playback |
| `flutter_local_notifications` | Local notifications |
| `timezone` | Time-zone-aware notification scheduling |
| `shared_preferences` | Persistent local settings and data |
| `permission_handler` | Runtime permission management |

## ⚙️ Native Android Integration

G-Lanterns 3D includes custom Android functionality implemented in Kotlin to improve immersion and device-level integration.

### Audio Management
- A mute watchdog in `MainActivity.kt` manages selected Android audio streams while speech recognition is active.
- Lantern sound effects are routed through the alarm audio stream to help preserve playback when media audio is muted.
- Audio behavior depends on Android version, device configuration, and system restrictions.

### Advanced Haptics
- Custom native vibration effects provide more expressive tactile feedback.
- Android's `VibrationEffect.Composition` API is used on supported devices to create detailed vibration patterns.
- Actual haptic effects vary depending on device hardware and Android API support.

### Background Battery Tracking
- Battery depletion is calculated using elapsed real-world time rather than relying solely on a continuously running timer.
- Persisted state allows the app to calculate the expected charge after periods spent in the background or with the app closed.
- Scheduled notifications depend on Android notification permissions, alarm restrictions, and device power-management policies.

## 📋 Prerequisites

Before running the project, make sure you have:

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Dart SDK](https://dart.dev/get-dart) (included with Flutter)
- [Android Studio](https://developer.android.com/studio) or another supported Flutter development environment
- Android SDK and a compatible Android device or emulator
- Git

## 🚀 Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/saqibmukadam/G-Lanterns-3D.git
```


### 2. Navigate to the project directory

```bash
cd G-Lanterns-3D
```

### 3. Install dependencies

```bash
flutter pub get
```

### 4. Verify the project

```bash
flutter doctor
```

Resolve any required SDK or toolchain issues reported by Flutter before proceeding.

### 5. Check connected devices

```bash
flutter devices
```

Connect your Android phone with USB debugging enabled or start a compatible emulator.

### 6. Run the application

```bash
flutter run
```

## 📁 Assets

The application requires the assets referenced in `pubspec.yaml`. Depending on the project configuration, these may include:

- **3D models:** `.glb` files for the Green Lantern Power Batteries.
- **Audio:** `.mp3` or other supported sound files for voiceovers and effects.
- **Images:** Lantern artwork, comic panels, backgrounds, and interface graphics.

Ensure the required assets exist at their configured paths and are correctly declared in `pubspec.yaml` before building the app.

## 🔐 Permissions

The application may request the following Android permissions, depending on the features enabled:

| Permission | Purpose |
|---|---|
| Microphone | Voice recognition and acoustic knock detection |
| Notifications | Low-battery alerts |
| Exact alarms | More precise notification scheduling where supported |
| Vibration | Custom haptic feedback |

Permissions must be declared and requested appropriately. Exact-alarm access and background execution are subject to Android version-specific restrictions and user settings.

## 📦 Building the APK

To generate a debug APK for testing:

```bash
flutter build apk --debug
```

To generate a release APK:

```bash
flutter build apk --release
```

The APK is typically generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For a Play Store release, configure application signing and build an Android App Bundle:

```bash
flutter build appbundle --release
```

See the [Flutter Android deployment guide](https://docs.flutter.dev/deployment/android) for signing, release configuration, and publishing instructions.

## 🧪 Development Notes

- Test voice recognition in a quiet environment and verify that the correct oath is recognized.
- Test background battery calculations after closing and reopening the application.
- Verify notification behavior on the target Android versions and devices.
- Optimize large `.glb` models to reduce download size, memory usage, and loading times.
- Test audio routing and haptic feedback on physical devices, since emulator behavior may differ.

## 🤝 Contributing

Contributions, bug reports, and feature suggestions are welcome.

1. Fork the repository.
2. Create a feature branch.
3. Make your changes and test them.
4. Submit a pull request describing your changes.

## 👤 Author

**Saqib Moin Mukadam**

## ⚖️ Disclaimer

G-Lanterns 3D is a fan-made simulator inspired by the Green Lantern universe. Green Lantern and related characters, names, symbols, and associated intellectual property belong to their respective rights holders. This project is not affiliated with or endorsed by DC or Warner Bros.

---

*Harness the power of will. Become the light.* 🟢
