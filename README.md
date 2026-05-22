# Build Flutter App

A composite GitHub Action that builds a distributable Flutter artifact:

- **iOS** → a signed `.ipa`
- **Android** → a signed `.apk`, `.aab` (App Bundle), or both

It installs the Flutter version pinned in your `pubspec.yaml`, restores
dependencies, optionally activates FlutterFire, sets up code signing from your
repository secrets, and runs the release build. Flavors are supported on both
platforms.

> The Flutter version is read from your `pubspec.yaml`
> (`flutter-version-file`), so the action always matches your project.

---

## Requirements

| Platform | Runner | Notes |
| -------- | ------ | ----- |
| `ios`     | `macos-latest` | Xcode is required; the action selects the latest installed Xcode. |
| `android` | `ubuntu-latest` or `macos-latest` | The action installs Temurin JDK 17. |

Your Flutter project must declare its Flutter version in `pubspec.yaml`, e.g.:

```yaml
environment:
  sdk: ^3.5.0
  flutter: 3.24.0
```

---

## Quick start

### iOS

```yaml
jobs:
  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - uses: crianpiro/build_flutter_app@v2
        with:
          platform: ios
          working-directory: example
          certificate-base64: ${{ secrets.P12_BASE64 }}
          certificate-password: ${{ secrets.P12_PASSWORD }}
          provisioning-profile-base64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
          keychain-password: ${{ secrets.RUNNER_KEYCHAIN_PASSWORD }}
          export-options-plist: ${{ secrets.EXPORT_OPTIONS }}
```

### Android

```yaml
jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: crianpiro/build_flutter_app@v2
        with:
          platform: android
          working-directory: example
          android-output: aab        # apk | aab | both
          android-keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          android-keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          android-key-password: ${{ secrets.ANDROID_KEY_PASSWORD }}
          android-key-alias: ${{ secrets.ANDROID_KEY_ALIAS }}
```

---

## Inputs

### Common

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `platform` | no | `ios` | Which platform to build: `ios` or `android`. |
| `working-directory` | no | `./` | Root of the Flutter app within the repository. |
| `flavor` | no | – | Name of the flavor to build. When set, the build targets `lib/flavors/main_<flavor>.dart`. |
| `bundle-id` | no | – | Bundle identifier of the flavor to build. |
| `use-flutterfire` | no | `"true"` | Whether to activate the FlutterFire CLI before building. |

### iOS (required when `platform: ios`)

| Name | Description |
| ---- | ----------- |
| `certificate-base64` | Base64 of the `.p12` signing certificate. |
| `certificate-password` | Password for the `.p12` certificate. |
| `provisioning-profile-base64` | Base64 of the `.mobileprovision` provisioning profile. |
| `export-options-plist` | Contents of the `ExportOptions.plist` (with your provisioning profile mapped). |
| `keychain-password` | Password used to create the temporary runner keychain. |

### Android (required when `platform: android`)

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `android-output` | no | `aab` | Artifact to produce: `apk`, `aab`, or `both`. |
| `android-keystore-base64` | yes | – | Base64 of the release keystore (`.jks` / `.keystore`). |
| `android-keystore-password` | yes | – | Keystore password (`storePassword`). |
| `android-key-password` | yes | – | Signing key password (`keyPassword`). |
| `android-key-alias` | yes | – | Alias of the signing key within the keystore. |

The action validates inputs before building and fails fast with a clear message
if `platform` / `android-output` is invalid or a required secret is missing for
the selected platform.

---

## Outputs / artifact locations

The build is verified at the end of the run; if the expected file is missing the
step fails. Locations are relative to `working-directory`:

| Platform | File |
| -------- | ---- |
| iOS | `build/ios/ipa/app-release.ipa` (or `app-<flavor>-release.ipa`) |
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` (or `app-<flavor>-release.apk`) |
| Android AAB | `build/app/outputs/bundle/release/app-release.aab` (or `app-<flavor>Release/app-<flavor>-release.aab`) |

To keep the artifact after the job, upload it:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: android-release
    path: example/build/app/outputs/bundle/release/*.aab
```

---

## Setting up signing

### iOS

The action expects the signing material as repository secrets. Encode each file
as Base64 (no line wrapping):

```bash
# .p12 certificate
base64 -i Certificates.p12 | pbcopy            # → P12_BASE64

# provisioning profile
base64 -i profile.mobileprovision | pbcopy     # → PROVISIONING_PROFILE_BASE64
```

`export-options-plist` is the **contents** of an `ExportOptions.plist` mapping
your bundle id to its provisioning profile, for example:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.example.buildFlutterApp</key>
    <string>Your Provisioning Profile Name</string>
  </dict>
</dict>
</plist>
```

Store the whole XML as the `EXPORT_OPTIONS` secret. `certificate-password`
(`P12_PASSWORD`) and `keychain-password` (`RUNNER_KEYCHAIN_PASSWORD`) are plain
strings — the keychain password can be any value you choose; it only protects
the temporary keychain created on the runner.

### Android

1. **Create a keystore** (skip if you already have one):

   ```bash
   keytool -genkey -v -keystore release-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. **Base64-encode it** for the secret:

   ```bash
   base64 -i release-keystore.jks | pbcopy        # → ANDROID_KEYSTORE_BASE64
   ```

3. **Add the secrets**: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`
   (the `-storepass`), `ANDROID_KEY_PASSWORD` (the `-keypass`), and
   `ANDROID_KEY_ALIAS` (e.g. `upload`).

4. **Wire your Gradle build to read `key.properties`.** The action decodes the
   keystore on the runner and writes `android/key.properties`, but your project's
   `android/app/build.gradle(.kts)` must consume it. This is the standard Flutter
   release-signing setup:

   <details>
   <summary><code>build.gradle.kts</code> (Kotlin DSL)</summary>

   ```kotlin
   import java.io.FileInputStream
   import java.util.Properties

   val keystoreProperties = Properties()
   val keystorePropertiesFile = rootProject.file("key.properties")
   if (keystorePropertiesFile.exists()) {
       keystoreProperties.load(FileInputStream(keystorePropertiesFile))
   }

   android {
       signingConfigs {
           create("release") {
               if (keystorePropertiesFile.exists()) {
                   keyAlias = keystoreProperties["keyAlias"] as String?
                   keyPassword = keystoreProperties["keyPassword"] as String?
                   storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                   storePassword = keystoreProperties["storePassword"] as String?
               }
           }
       }
       buildTypes {
           release {
               signingConfig = if (keystorePropertiesFile.exists())
                   signingConfigs.getByName("release")
               else
                   signingConfigs.getByName("debug")
           }
       }
   }
   ```
   </details>

   The bundled [`example`](./example) project is already configured this way.
   Without this wiring, Gradle ignores the injected keystore and the release is
   debug-signed.

---

## Flavors

Set the `flavor` input to build a flavored release. The action expects an entry
point at `lib/flavors/main_<flavor>.dart` and runs, for example:

```
flutter build appbundle --release --flavor staging --target lib/flavors/main_staging.dart
```

Leave `flavor` unset for a single-flavor app.

---

## Building both platforms

Use a matrix or two jobs (iOS must run on macOS):

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
          - platform: ios
            os: macos-latest
          - platform: android
            os: ubuntu-latest
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: crianpiro/build_flutter_app@v2
        with:
          platform: ${{ matrix.platform }}
          working-directory: example
          # iOS secrets (used when platform == ios)
          certificate-base64: ${{ secrets.P12_BASE64 }}
          certificate-password: ${{ secrets.P12_PASSWORD }}
          provisioning-profile-base64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
          keychain-password: ${{ secrets.RUNNER_KEYCHAIN_PASSWORD }}
          export-options-plist: ${{ secrets.EXPORT_OPTIONS }}
          # Android secrets (used when platform == android)
          android-output: both
          android-keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          android-keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          android-key-password: ${{ secrets.ANDROID_KEY_PASSWORD }}
          android-key-alias: ${{ secrets.ANDROID_KEY_ALIAS }}
```

---

## Example

This repository includes a runnable [`example/`](./example) Flutter app and a
workflow at [`.github/workflows/launch.yaml`](./.github/workflows/launch.yaml)
that builds it on every push to `main`.

## License

[BSD 3-Clause](./LICENSE) © Cristian Andres Picon Rodriguez
