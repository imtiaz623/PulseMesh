# PulseMesh v1.0 (Flutter + Kotlin)

Offline peer-to-peer messenger for Android. No internet, no servers. Uses Google
Nearby Connections (`Strategy.P2P_CLUSTER`), which combines BLE, Bluetooth Classic
and Wi-Fi under the hood. The link between two phones is encrypted by Nearby.

## Project structure
```
pulsemesh/
  pubspec.yaml
  lib/
    main.dart               app entry, lifecycle hook
    theme.dart              midnight slate + electric indigo
    models.dart             Peer, Message, MsgStatus
    db.dart                 SQLite (peers + messages = offline queue)
    mesh_service.dart       permissions, Bluetooth, service, Nearby, queue, acks, media
    widgets.dart            avatar, ticks, link bars, banner, status chip
    screens/
      home_shell.dart       bottom nav + Chats tab
      radar_screen.dart     Radar tab
      settings_screen.dart  Settings & Profile tab
      chat_screen.dart      conversation view
  android/app/src/main/
    AndroidManifest.xml
    kotlin/com/pulsemesh/pulsemesh/MainActivity.kt   Bluetooth enable prompt, service control
    kotlin/com/pulsemesh/pulsemesh/MeshService.kt    foreground service + notification
```

## Setup
1. `flutter create --org com.pulsemesh --project-name pulsemesh pulsemesh`
   (the Kotlin package must be `com.pulsemesh.pulsemesh`)
2. Copy `lib/`, `pubspec.yaml`, and the two Kotlin files + `AndroidManifest.xml`
   from this folder over the generated project. Delete the generated `test/widget_test.dart`.
3. In `android/app/build.gradle(.kts)` set:
   ```
   minSdk = 23        // Kotlin DSL  (Groovy: minSdkVersion 23)
   compileSdk = 34    // or higher
   targetSdk = 34
   ```
   Google Play Services Nearby (`com.google.android.gms:play-services-nearby`) is pulled in
   automatically by the `nearby_connections` plugin. No other Gradle dependency is needed.
4. `flutter pub get`, then `flutter run` on **two physical Android phones**
   (emulators have no usable Bluetooth/Wi-Fi radios). Phones need Google Play Services.

## Honest limits of v1.0
- **Not compiled or device-tested by the author of this package.** Expect to fix small
  API mismatches (plugin versions move). Test file transfer first.
- **No silent Bluetooth enable.** Android 13+ forbids it; the app shows the system
  "turn on Bluetooth" dialog automatically at startup and when it is switched off.
- **No dBm.** Nearby Connections does not expose RSSI. Radar rings and bars use
  measured round-trip latency instead.
- **Direct links only.** P2P_CLUSTER connects many-to-many but does not relay between
  phones that cannot reach each other. Multi-hop routing is not in v1.0.
- **Range** is whatever the radios give: 50-100 m only in open air.
- **Background** = app minimised/screen off, kept alive by the foreground service.
  Swiping the app out of recents stops the Dart engine (and the service stops with it).
  A fully swipe-proof design needs Nearby moved into the native service.
- Received media is copied out of the plugin's temp location; on some Android versions
  the plugin may need storage access to write that temp file.
- Connections are auto-accepted for PulseMesh nodes; no pairing-code check yet.
