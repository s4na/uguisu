#!/bin/bash

# uguisu インストールスクリプト
# macOSのGatekeeper制限を解除してアプリをApplicationsフォルダにインストールします

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="uguisu.app"
APP_PATH="$SCRIPT_DIR/$APP_NAME"
DEST_PATH="/Applications/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "エラー: $APP_NAME が見つかりません"
    echo "このスクリプトは uguisu.app と同じフォルダで実行してください"
    exit 1
fi

echo "uguisu をインストールしています..."

# quarantine属性を削除
echo "→ セキュリティ属性を解除中..."
xattr -cr "$APP_PATH"

# Applicationsフォルダにコピー
echo "→ アプリケーションフォルダにコピー中..."
if [ -d "$DEST_PATH" ]; then
    rm -rf "$DEST_PATH"
fi
cp -R "$APP_PATH" "$DEST_PATH"

echo ""
echo "✓ インストール完了!"
echo ""
echo "次のステップ:"
echo "1. アプリケーションフォルダから uguisu を起動"
echo "2. 初回起動時に Accessibility 権限を許可"
echo ""
