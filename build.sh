#!/bin/sh
# 构建可刷 zip：./build.sh → charge-guard-v<ver>.zip
set -e
cd "$(dirname "$0")"
VER=$(grep '^version=' module/module.prop | cut -d= -f2)
OUT="charge-guard-v$VER.zip"
rm -rf pkg && mkdir -p pkg/META-INF/com/google/android
cp META-INF/com/google/android/* pkg/META-INF/com/google/android/
cp customize.sh module/module.prop module/service.sh module/supervise.sh module/policy.sh module/charge-guard.sh uninstall.sh pkg/
chmod 755 pkg/META-INF/com/google/android/update-binary pkg/*.sh
cd pkg && zip -r -9 "../$OUT" . -x '.*' && cd ..
echo "built: $OUT"
