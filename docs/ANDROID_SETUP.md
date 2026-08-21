**File: ANDROID_SETUP.md**

````markdown
# Android Google Sign-In Configuration Guide (Fix for ApiException 10)

If you are encountering `com.google.android.gms.common.api.ApiException: 10` (DEVELOPER_ERROR) when attempting to sign in with Google on Android, it indicates a mismatch between your Android app's signing certificate and the configuration in the Google Cloud/Firebase Console.

**Web works but Android fails?** Web uses a separate OAuth client (no SHA-1). Android requires the **exact** SHA-1 of the keystore that signs your APK in **two** places: (1) Firebase Project settings → Your apps → Android app → Add fingerprint, and (2) Google Cloud Console → APIs & Services → Credentials → an **Android** OAuth client with the same package name and SHA-1. If either is missing or has a typo (e.g. `8a` instead of `0A`), you get ApiException 10.

**Same SHA-1 in Console but still ApiException 10?** The app is signed with the keystore that **this machine** uses when you run `flutter run` or build the APK. That can differ from the SHA-1 you registered if: (1) you added the fingerprint from another computer, (2) the debug keystore was recreated (e.g. new Android Studio install, new user), or (3) you're testing a build installed from Play Store (Google re-signs it — use the **App signing key** SHA-1 from Play Console). **Fix:** On the machine where you build and run the app, run `cd android && ./gradlew signingReport` and compare the **Variant: debug** SHA1 to the one in Firebase. If they differ, add the **report’s** SHA-1 to Firebase and to the Android OAuth client, re-download `google-services.json`, then `flutter clean`, `./gradlew clean`, and run again.

Follow these steps to resolve the issue.

## Prerequisites: Java (JDK 17)

Gradle (used for Android builds) requires a Java runtime. If you see “Unable to locate a Java Runtime” when running `./gradlew`:

**Option A – Homebrew (macOS):**

1. Fix Homebrew permissions if needed:
   ```bash
   sudo chown -R $(whoami) /opt/homebrew /Users/$(whoami)/Library/Logs/Homebrew
   ```
2. Install OpenJDK 17:
   ```bash
   brew install openjdk@17
   ```
3. Use this Java for the current shell (Apple Silicon):
   ```bash
   export JAVA_HOME=/opt/homebrew/opt/openjdk@17
   ```
   (Intel Macs: use `export JAVA_HOME=/usr/local/opt/openjdk@17`)

**Option B – Manual install:**  
Download and install [Eclipse Temurin JDK 17](https://adoptium.net/temurin/releases/?version=17) or use the JDK bundled with [Android Studio](https://developer.android.com/studio) (often under `Android Studio.app/Contents/jbr/Contents/Home`).

Then run `./gradlew signingReport` from the `android` directory.

---

## 1. Generate SHA-1 Fingerprints

You need to register the SHA-1 fingerprint of the keystore used to sign your app (both debug and release).

1.  Open a terminal in the project root.
2.  Navigate to the `android` directory:
    ```bash
    cd android
    ```
3.  Run the signing report task:

    ```bash
    ./gradlew signingReport
    ```

    _(Windows users: run `gradlew signingReport`)_

4.  Look for the output section labeled **Variant: debug**. Copy the **SHA1** fingerprint. It looks like this:
    `SHA1: DA:39:A3:EE:5E:6B:4B:0D:32:55:BF:EF:95:60:18:90:AF:D8:07:09`
    49:25:B7:05:BF:EC:C2:6F:1F:7C:9F:0A:DD:BC:62:BD:5D:5E:DE:43

## 2. Register Fingerprints in Firebase / Google Cloud

1.  Go to the [Firebase Console](https://console.firebase.google.com/).
2.  Select your project.
3.  Click the **Gear icon** > **Project settings**.
4.  Scroll down to the **Your apps** section and select the Android app (`com.example.krag_app`).
5.  Click **Add fingerprint**.
6.  Paste the SHA-1 fingerprint you copied in Step 1.
7.  **Save**.

> **Note:** If you are using a release build, ensure you also add the SHA-1 from your release keystore.

## 3. Update `google-services.json`

Although adding the fingerprint is often enough, it is best practice to ensure your local configuration file is up to date.

1.  In the Firebase Console **Project settings** > **Your apps** section, download the latest `google-services.json`.
2.  Replace the existing file in your project:
    `android/app/google-services.json`

## 4. Verify Package Name

Ensure the `applicationId` in your `android/app/build.gradle` matches exactly what is registered in Firebase.

File: `android/app/build.gradle`

```gradle
defaultConfig {
    applicationId "com.example.krag_app"
    // ...
}
```
````

## 5. Verify OAuth Consent Screen

1.  Go to the [Google Cloud Console](https://console.cloud.google.com/).
2.  Select your project.
3.  Navigate to **APIs & Services** > **OAuth consent screen**.
4.  Ensure the **User Type** is set correctly (usually "External" for testing, or "Internal" for org-specific).
5.  Under **Scopes**, ensure the following are added:
    - `.../auth/drive.file` (Google Drive API)
    - `email`
    - `profile`
    - `openid`
6.  **Important:** If your app is in "Testing" mode, ensure your email address is added to the **Test users** list.

## 6. Clean and Rebuild

After making these changes, clean your build to ensure cached configurations are cleared.

```bash
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run
```

```

✅ Step 1 completed: Generate Android Configuration Guide

Ready for next step. Please select a step number ([2]) to execute, 'all' to run remaining, or 'q' to quit.
```

1. SHA-1 typo in Firebase
   The SHA-1 in Firebase is:
   49:25:b7:05:bf:ec:c2:6f:1f:7c:9f:8a:dd:bc:62:bd:5d:5e:de:43
   ^^ wrong
   Your debug keystore’s SHA-1 is:
   49:25:B7:05:BF:EC:C2:6F:1F:7C:9F:0A:DD:BC:62:BD:5D:5E:DE:43
   ^^ correct (zero-A)
   8a should be 0a (zero + A).
   Fix: In Firebase → Project settings → Your apps → Krag, remove the existing fingerprint and add this one:
   49:25:B7:05:BF:EC:C2:6F:1F:7C:9F:0A:DD:BC:62:BD:5D:5E:DE:43
2. No OAuth clients in Google Cloud
   The OAuth overview says: “You haven't configured any OAuth clients for this project yet.”
   Google Sign-In needs an Android OAuth client:
   In Google Cloud Console → select Krag.
   Go to APIs & Services → Credentials.
   Click Create Credentials → OAuth client ID.
   Choose Application type: Android.
   Set:
   Name: e.g. Krag Android
   Package name: com.example.krag_app
   SHA-1 certificate fingerprint: 49:25:B7:05:BF:EC:C2:6F:1F:7C:9F:0A:DD:BC:62:BD:5D:5E:DE:43
   Click Create.
3. After both changes
   Re-download google-services.json from Firebase (Project settings → Your apps → Krag → download).
   Replace android/app/google-services.json with the new file.
   Clean and run:
   flutter clean
   flutter pub get
   cd android && ./gradlew clean && cd ..
   flutter run
   flutter cleanflutter pub getcd android && ./gradlew clean && cd ..flutter run
   Both the corrected SHA-1 and the Android OAuth client must be set up for sign-in to work.

poikjh01
