Here is the clean-up sequence to fix it:
flutter pub add -d hive_generator

1.  **Clean the project and cache:**

    ```bash
    flutter clean
    rm -rf .dart_tool
    ```

2.  **Re-fetch dependencies:**

    ```bash
    flutter pub get
    ```

3.  **Run the generator (using the modern command):**
    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```

timestamp=$(date +%Y-%m-%d) && git archive --format=zip --output="../krag-kms-app-$timestamp-v1.0.2.zip" HEAD

### Build models

flutter pub run build_runner build
flutter pub run build_runner build --delete-conflicting-outputs

### Test

flutter test

flutter pub get
flutter pub upgrade
flutter pub upgrade --major-versions

flutter build appbundle
flutter build apk

WEB:
npm install -g surge
flutter build web
surge build/web
craven-oatmeal.surge.sh

flutter build apk --flavor dev \
 --dart-define=ENABLE_SUBSCRIPTIONS=true \
 --dart-define=API_BASE_URL=https://dev.api.com

##certificate
keytool -genkey -v -keystore ./release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias release-alias

./key.properties
storePassword=
keyPassword=
keyAlias=key
storeFile=../../key.jks

keytool -list -v -keystore key.jks

flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk

flutter clean
flutter build apk --release
flutter build apk --debug
