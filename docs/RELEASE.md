# Release: signing and installing the APK (Phase 6.5, ADR-034)

This is a **pilot** release for a few friends, outside any store. The app id is
`io.github.hedefender.simpledocscan`. The signing key never enters the repository.

## 1. How the signing works

`android/app/build.gradle.kts` reads `android/key.properties` when it exists:

```
storeFile=C:\\dev\\keys\\simpledocscan-release.jks
storePassword=...
keyAlias=simpledocscan
keyPassword=...
```

- **With** `key.properties`: `flutter build apk --release` is signed with your key.
- **Without** it: the release build is signed with the **debug key** and Gradle prints
  `WARNING: release signed with debug key, not for distribution`. Anyone who clones the
  repository can build; nobody should distribute that APK. (Flutter hides Gradle warnings
  unless you add `-v`; the check below, `apksigner verify`, always tells the truth.)
- `android/key.properties.example` shows the format. `key.properties`, `*.jks` and
  `*.keystore` are in `.gitignore` (checked with `git check-ignore`). **Never commit them.**
- The file is read from `android/`, but the keystore itself lives **outside** the repository.

## 2. Making the key (once, by you, in PowerShell)

Keep the keystore outside the repository, for example in `C:\dev\keys\`:

```powershell
New-Item -ItemType Directory -Force C:\dev\keys
keytool -genkeypair -v -storetype PKCS12 `
  -keystore C:\dev\keys\simpledocscan-release.jks `
  -alias simpledocscan -keyalg RSA -keysize 4096 -validity 10000
```

`keytool` asks for a password and for your details (the details are written into the
certificate, so use what you are happy to have inside every APK). In a PKCS12 keystore the key
uses the **same password as the store**, so write the same value in `storePassword` and
`keyPassword`. Then copy `android\key.properties.example` to `android\key.properties`
and fill it in. In `storeFile` write the path with doubled backslashes or with forward slashes.

> **If you lose the keystore or its passwords, the app can never be updated again under this
> id.** Android refuses an update signed with a different key; the friends would have to
> uninstall (and lose their settings) and install a new app. So:
>
> - keep **two backups** of the `.jks` in two different places (for example an encrypted USB
>   stick and a private cloud folder), never in the repository;
> - keep the passwords and the alias in a **password manager**;
> - note the SHA-256 of the certificate (`keytool -list -v -keystore ...`) in the password
>   manager too, to recognise the right key later.

## 3. Building

```powershell
flutter build apk --release --split-per-abi
```

Output in `build\app\outputs\flutter-apk\`:

| File | For |
|---|---|
| `app-arm64-v8a-release.apk` | almost every phone of the last years: **send this one** |
| `app-armeabi-v7a-release.apk` | old 32-bit phones |
| `app-x86_64-release.apk` | emulators on a PC |

Sizes in Phase 6.5 (R8 on, models included): arm64-v8a 70.1 MB, armeabi-v7a 60.4 MB,
x86_64 77.4 MB.

Check the signature (the `apksigner` of the Android SDK `build-tools`, for example
`%LOCALAPPDATA%\Android\Sdk\build-tools\36.0.0\apksigner.bat`):

```powershell
apksigner verify --print-certs build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

The line `Signer #1 certificate DN` must show **your** details, not `CN=Android Debug`.
Install on your own phone with USB debugging:

```powershell
adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

The version shown in the app (About) comes from `version:` in `pubspec.yaml`
(`0.1.0+1`: name `+` build number). **Raise the build number for every APK you give out**,
or Android will refuse the update as a downgrade.

## 4. Instructions for friends

1. Download the APK (the arm64 one) on the phone. If the phone is very old and the install says
   the app is not compatible, use the armeabi-v7a one.
2. Open the file. Android asks to allow installing from this source (the browser or the files
   app you used): allow it for this once. The wording of the setting differs by maker
   ("Install unknown apps" / "Εγκατάσταση από άγνωστες πηγές").
3. Install, open, and follow the first-run wizard.
4. **Updates:** send a new APK with a higher build number and the same key; the friend installs
   it over the old one and keeps their settings. There is no automatic update.
5. The app is a pilot: it may have faults. "Send feedback" in Settings, About, opens an e-mail
   with the version of the app in it (only when the owner has set an address).

## 5. Things to know

- The new id is a **different app** for Android. It does not take the data or the settings of
  the old `com.example.one_click_scan` and can be installed next to it; the old one stays as it is.
- The same id is meant to be the bundle id on iOS later. No iOS files exist yet.
- Do not publish a build signed with the debug key and do not share `key.properties`.
