#!/bin/bash

APK=NativeExample.apk

if [ "${ANDROID_NDK}" == "" ]; then
  if [ "${ANDROID_NDK_VERSION}" == "" ]; then
    ANDROID_NDK_VERSION="26.1.10909125"
  fi
  ANDROID_NDK=~/Library/Android/sdk/ndk/$ANDROID_NDK_VERSION
fi

if [ "${ANDROID_SDK}" == "" ]; then
  ANDROID_SDK=~/Library/Android/sdk
fi

for DIR in $ANDROID_SDK/build-tools/*/
do
  ANDROID_BUILD_TOOLS=$DIR
done

for DIR in $ANDROID_SDK/platforms/*/
do
  ANDROID_PLATFORM=$DIR
done

JAVAC=javac
JARSIGNER=jarsigner
KEYTOOL=keytool
NDK_BUILD=${ANDROID_NDK}/ndk-build
ADB=${ANDROID_SDK}/platform-tools/adb
AAPT=${ANDROID_BUILD_TOOLS}/aapt
ZIPALIGN=$ANDROID_BUILD_TOOLS/zipalign
PLATFORM=$ANDROID_PLATFORM/android.jar

function check () {
  if [ ! -f $NDK_BUILD ]; then
    echo Android NDK not found in "$ANDROID_NDK"
    return 1
  fi

  if [ ! -d $ANDROID_SDK ]; then
    echo Android SDK not found in "$ANDROID_SDK"
    return 1
  fi

  which $JAVAC >> /dev/null
  if [ $? -ne 0 ]; then
    echo Java JDK not found in "$JAVA_JDK"
    return 1
  fi

  if [ ! -f $ADB ]; then
    echo Please install Android SDK Platform-tools
    return 1
  fi

  # :tools_ok
  if [ ! -f $AAPT ]; then
    echo Please install Android SDK Build-tools
    return 1
  fi

  # :platform_ok
  if [ ! -f $PLATFORM ]; then
    echo Please install at least one Android SDK platform
    return 1
  fi
}

function build () {
  if [[ ! -d bin ]]; then
    mkdir bin
  fi
  if [[ ! -d lib ]]; then
    mkdir lib
    mkdir lib/lib
  fi

  $NDK_BUILD -j4 NDK_LIBS_OUT=lib/lib
  if [ $? -ne 0 ]; then
    echo "ndk-build failed"
    return 1
  fi

  $AAPT package -f -M AndroidManifest.xml -I $PLATFORM -A assets -F bin/$APK.build lib
  if [ $? -ne 0 ]; then
    echo "AAPT failed"
    return 1
  fi

  if [ ! -f .keystore ]; then
    $KEYTOOL -genkey -dname "CN=Android Debug, O=Android, C=US" -keystore .keystore -alias androiddebugkey -storepass android -keypass android -keyalg RSA -validity 30000
    if [ $? -ne 0 ]; then
      echo "Keytool failed"
      return 1
    fi
  fi

  $JARSIGNER -storepass android -keystore .keystore bin/$APK.build androiddebugkey >nul
  if [ $? -ne 0 ]; then
    echo "jarsigner failed"
    return 1
  fi

  $ZIPALIGN -f 4 bin/$APK.build bin/$APK
  if [ $? -ne 0 ]; then
    echo "zipalign failed"
    return 1
  fi

  rm bin/$APK.build
}

install () {
  $ADB install -r bin/$APK || return 1
}

get_package_activity () {
  while IFS= read -r line; do
    tokens=($line)
    if [[ ${tokens[0]} == "package:" ]]; then
      PACKAGE=${tokens[1]//\'/}
      PACKAGE=${PACKAGE#name=}
    elif [[ ${tokens[0]} == "launchable-activity:" ]]; then
      ACTIVITY=${tokens[1]//\'/}
      ACTIVITY=${ACTIVITY#name=}
    fi
  done < <($AAPT dump badging bin/$APK)
}

launch () {
  get_package_activity
  $ADB shell am start -n $PACKAGE/$ACTIVITY
  if [ $? -ne 0 ]; then
    echo "adb failed"
    return 1
  fi
}

remove () {
  get_package_activity
  $ADB uninstall $PACKAGE
  if [ $? -ne 0 ]; then
    echo "adb uninstall failed"
    return 1
  fi
}

log () {
  $ADB logcat -d NativeExample:V *:S
  if [ $? -ne 0 ]; then
    echo "adb logcat failed"
    return 1
  fi
}

check || exit 1

if [ "$1" == "run" ]; then
  install || exit 1
  launch || exit 1
elif [ "$1" == "build" ]; then
  build || exit 1
elif [ "$1" == "remove" ]; then
  remove || exit 1
elif [ "$1" == "install" ]; then
  install || exit 1
elif [ "$1" == "launch" ]; then
  launch || exit 1
elif [ "$1" == "log" ]; then
  log || exit 1
elif [ "$1" == "" ]; then
  build || exit 1
  install || exit 1
  launch || exit 1
else
  echo
  echo Usage: $BASH_SOURCE [command]
  echo By default build, install and run .apk file.
  echo
  echo Optional [command] can be:
  echo "  run       - only install and run .apk file"
  echo "  build     - only build .apk file"
  echo "  remove    - remove installed .apk"
  echo "  install   - only install .apk file on connected device"
  echo "  launch    - ony run already installed .apk file"
  echo "  log       - show logcat"
fi