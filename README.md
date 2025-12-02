# uguisu

macOS向けの音声入力アプリケーション（開発中）

## 必要条件

- macOS 13.0 以上
- Accessibility権限（グローバルホットキー検出に必要）

## インストール

1. [Releases](https://github.com/s4na/uguisu/releases)から最新のzipをダウンロード
2. zipを展開
3. ターミナルで以下を実行:
   ```bash
   cd ~/Downloads/uguisu-vX.X.X  # 展開したフォルダに移動
   ./install.sh
   ```
4. 初回起動時にAccessibility権限を許可

### 手動インストール

インストールスクリプトを使わない場合:

1. ターミナルで quarantine 属性を削除:
   ```bash
   xattr -cr ~/Downloads/uguisu-vX.X.X/uguisu.app
   ```
2. `uguisu.app` をアプリケーションフォルダに移動
3. 右クリック →「開く」で初回起動

## 使い方

1. アプリを起動するとメニューバーにマイクアイコンが表示されます
2. **⌥ + Space** を押すとオーバーレイウィンドウが表示されます
3. **Esc** でオーバーレイを閉じます
4. メニューバーアイコンをクリックして設定やアプリの終了ができます

## 開発

### ビルド

```bash
xcodebuild build \
  -scheme uguisu \
  -configuration Debug \
  -destination 'generic/platform=macOS'
```

### 実行

Xcodeでプロジェクトを開き、実行ボタンをクリックするか `⌘ + R` を押してください。

## ライセンス

MIT