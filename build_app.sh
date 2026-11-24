#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 正在使用 Swift Release 模式构建 PixSnap..."
swift build -c release

echo "📦 正在打包 PixSnap.app..."
mkdir -p PixSnap.app/Contents/MacOS PixSnap.app/Contents/Resources
cp .build/release/PixSnap PixSnap.app/Contents/MacOS/PixSnap

# SwiftPM 默认把 LC_BUILD_VERSION 的 sdk 写成 Package.swift 的最低平台版本 (14.0)，
# 会导致 macOS 26+ 以旧版兼容模式渲染所有系统控件；这里写入本机 SDK 版本以启用原生 Liquid Glass。
SDK_VER="$(xcrun --show-sdk-version 2>/dev/null || true)"
if [ -n "$SDK_VER" ] && command -v vtool >/dev/null 2>&1; then
    vtool -set-build-version macos 14.0 "$SDK_VER" -replace \
        -output PixSnap.app/Contents/MacOS/PixSnap PixSnap.app/Contents/MacOS/PixSnap 2>/dev/null
    echo "✨ 已写入目标 SDK 版本 ($SDK_VER) 以启用原生 Liquid Glass 控件样式"
fi

echo "🔏 正在进行稳定代码签名..."
# 可通过 PIXSNAP_SIGN_IDENTITY 指定签名证书；未指定时自动选用钥匙串中的第一个 Apple Development 证书
CERT="${PIXSNAP_SIGN_IDENTITY:-$(security find-identity -p codesigning -v | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/')}"
if [ -n "$CERT" ]; then
    codesign --force --deep --sign "$CERT" PixSnap.app
    echo "✅ 已使用你的 Apple Developer 证书签名（重编无需再重复授权！）"
else
    codesign --force --deep --sign - --requirements '=designated => identifier "com.wangqi.pixsnap"' PixSnap.app
    echo "⚠️ 使用固定 Identifier 签名"
fi

echo "✅ 构建完成！应用路径: $DIR/PixSnap.app"
