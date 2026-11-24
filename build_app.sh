#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 正在使用 Swift Release 模式构建 PixSnap..."
swift build -c release

echo "📦 正在打包 PixSnap.app..."
mkdir -p PixSnap.app/Contents/MacOS PixSnap.app/Contents/Resources
cp .build/release/PixSnap PixSnap.app/Contents/MacOS/PixSnap

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
