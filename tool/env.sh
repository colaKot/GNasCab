# GNasCab dev environment for Git Bash  (source it, do not exec)
#   usage:  source /g/work/nascab/tool/env.sh
export TOOLCHAIN="/g/work/_toolchain"
export FLUTTER_ROOT="$TOOLCHAIN/flutter-3.38.10/flutter"
export JAVA_HOME='G:\work\_toolchain\jdk17\jdk-17.0.20.1+1'
export ANDROID_HOME='G:\work\_toolchain\android-sdk'
export ANDROID_SDK_ROOT="$ANDROID_HOME"

# China mirrors
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export FLUTTER_SUPPRESS_ANALYTICS=true

export PATH="$FLUTTER_ROOT/bin:$PATH"

echo "[GNasCab] Flutter : $FLUTTER_ROOT"
echo "[GNasCab] JDK     : $JAVA_HOME"
echo "[GNasCab] Android : $ANDROID_HOME"
