#!/usr/bin/env bash
# Creates the Android and Windows host projects with `flutter create` (they are
# generated, not checked in) and applies Margin's few changes to them.
# Run from anywhere: bash android-windows/tool/prepare_platforms.sh
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name margin --org de.margin --platforms=android,windows --no-pub .
# The template adds a counter-app test that doesn't apply to Margin.
rm -f test/widget_test.dart

manifest=android/app/src/main/AndroidManifest.xml
# Internet for sync and link titles (the template only allows it in debug builds).
if ! grep -q 'android.permission.INTERNET' "$manifest"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"
fi
sed -i 's#android:label="margin"#android:label="Margin"#' "$manifest"

# Window title and Margin.exe on Windows.
sed -i 's#L"margin"#L"Margin"#' windows/runner/main.cpp
sed -i 's#set(BINARY_NAME "margin")#set(BINARY_NAME "Margin")#' windows/CMakeLists.txt

# Release signing: a stable key from the repository secrets, if there is one
# (otherwise Gradle signs with a throw-away debug key, see README).
if [[ -n "${ANDROID_KEYSTORE_B64:-}" ]]; then
  echo "$ANDROID_KEYSTORE_B64" | base64 -d > android/app/margin-release.p12
  cat > android/key.properties <<PROPS
storeFile=margin-release.p12
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS:-margin}
keyPassword=${ANDROID_KEYSTORE_PASSWORD}
PROPS
  gradle=android/app/build.gradle.kts
  if ! grep -q 'margin-release' "$gradle"; then
    python3 - "$gradle" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
signing = '''
    signingConfigs {
        create("marginRelease") {
            val props = java.util.Properties()
            props.load(rootProject.file("key.properties").inputStream())
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            storeType = "pkcs12"
        }
    }
'''
text = text.replace("    buildTypes {", signing + "\n    buildTypes {", 1)
text = text.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("marginRelease") // margin-release', 1)
open(path, "w").write(text)
PY
  fi
fi
echo "Platforms ready."
