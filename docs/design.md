# uguisu – macOS Voice Shortcut Input App Design

> **Project Name**: `uguisu`
> **Tagline**: “Hit a shortcut, speak, hit Enter, text appears where you were typing.”

---

## 1. Overview

uguisu は、macOS 上でグローバルショートカットを押すと立ち上がる「一時的な音声入力ランチャー」です。

1. ユーザーが任意のアプリ（エディタ、ブラウザ、チャットツールなど）で入力中にグローバルショートカットを押す
2. 画面中央付近に小さなオーバーレイウィンドウが表示される
3. 即座に録音開始（またはスペースキーなどで録音開始）
4. 音声を STT（Speech-to-Text）モデルで文字起こし
5. テキストがオーバーレイに表示される（リアルタイム or 録音終了後）
6. `Enter` を押すと、テキストが「元のアプリのカーソル位置」に入力される
7. `Esc` でキャンセルして元のアプリに戻る

STT モデルは複数（ローカル / クラウド問わず）を切り替え可能で、設定画面から選択・追加できる。

---

## 2. Goals

* macOS 上で **任意のアプリから素早く音声入力を呼び出せる** ようにする
* 変換されたテキストを **元のフォーカス位置に自然に入力** できること
* **複数の STT モデルを簡単に切り替え** られる拡張性の高い設計
* 入力体験が「タイピングより速く・楽」だと感じられる UX
* プライバシーとセキュリティを意識し、音声データやテキストを安全に扱う

---

## 3. Non-Goals

* モバイル / Windows / Linux のサポート（初期スコープ外）
* 会議録のような **長時間録音**（数十分〜数時間）はサポートしない
* 高度な編集機能（Markdown プレビューやエディタ機能）は持たない
* 独自の STT モデル学習・ファインチューニング機能の実装

---

## 4. User Stories

1. **US-01: ショートカットから即音声入力**

   * 「テキストエディタで文章を書いているとき、ショートカットを押すだけで音声入力ウィンドウが開き、話し終わって Enter でテキストが挿入されてほしい。」

2. **US-02: モデル切り替え**

   * 「精度やレイテンシ、コストに応じて `Whisper-local` と `Cloud-STT` を切り替えたい。」

3. **US-03: リアルタイムプレビュー**

   * 「しゃべっている途中から、リアルタイムでテキストが見えると安心できる。」

4. **US-04: 入力キャンセル**

   * 「変換結果が気に入らないときは Esc でキャンセルして、元のアプリにそのまま戻りたい。」

5. **US-05: マイクや権限エラー**

   * 「初回起動時に必要な権限をわかりやすく案内してほしい。問題が起きたときもシンプルなエラーメッセージがほしい。」

6. **US-06: モデル設定管理**

   * 「API キーやエンドポイントの設定を GUI から追加・編集したい。複数モデルを登録しておき、ショートカットやドロップダウンで切り替えたい。」

---

## 5. UX / Interaction Design

### 5.1 全体フロー（ハイレベル）

1. ユーザーが任意のアプリでテキストカーソルを置いている状態
2. グローバルショートカット（例: `⌘ + ⇧ + Space`）を押す
3. uguisu のオーバーレイウィンドウが表示される

   * フローティング、中央 or カーソル近く
4. 録音開始

   * オプション A: ウィンドウ表示と同時に録音開始
   * オプション B: Space キーで録音開始 / 再度 Space で停止
5. 音声 → テキスト変換（STT モデル）
6. テキストプレビュー

   * 完了後に一括表示
   * or ストリーミングで逐次更新
7. `Enter`:

   * オーバーレイが閉じる
   * テキストが元アプリに挿入される
8. `Esc`:

   * オーバーレイを閉じてキャンセル
   * 何も挿入しない

### 5.2 ウィンドウ UI

* コンポーネント例

  * 上部: 現在の STT モデル名（例: `Model: Whisper (local)`）、モデル切り替えボタン
  * 中央: テキスト表示エリア（変換結果）
  * 下部: ステータス・操作

    * `● Recording...` / `■ Ready`
    * ショートカットヘルプ（`Enter = Insert`, `Esc = Cancel`, `Space = Start/Stop`）
* サイズ

  * デフォルト: 幅 ~600px, 高さ ~200–300px
  * リサイズ可能（将来対応）

### 5.3 状態遷移（シンプル版）

* `Idle`（常駐・アイコンのみ）

  * グローバルショートカット → `OverlayOpening`
* `OverlayOpening`

  * ウィンドウ表示 → `Ready`
* `Ready`

  * `Space` or auto-start → `Recording`
  * `Esc` → `Closing`
* `Recording`

  * `Space` orタイムアウト → `Transcribing`
  * `Esc` → `Closing`（録音破棄）
* `Transcribing`

  * STT 完了 → `Preview`
  * エラー → `Error`
* `Preview`

  * `Enter` → `InsertAndClose`
  * `Esc` → `Closing`
* `InsertAndClose`

  * テキスト挿入成功 → `Idle`
  * 失敗 → `Error`（ただしウィンドウは閉じる）
* `Error`

  * ユーザー確認後 → `Idle`
* `Closing`

  * ウィンドウ閉じる → `Idle`

---

## 6. Functional Requirements

### 6.1 グローバルショートカット

* macOS のどのアプリ上でもショートカットを受け取れる
* 設定画面からショートカット変更可能
* ショートカットが既存アプリのショートカットと衝突した場合の考慮（可能なら検出）

### 6.2 音声録音

* システムのデフォルトマイクを利用
* サンプリング: 16kHz or 44.1kHz（モデルに合わせて変換）
* フォーマット: PCM (WAV) / その他モデル仕様に合わせる
* 録音時間の上限（例: 30秒〜60秒）
* 録音中は視覚的フィードバック（波形 or レベルメーター）

### 6.3 STT モデル呼び出し

* 音声データを `STTEngine` 抽象インタフェースに渡す
* 同一インタフェースで複数バックエンドを扱う

  * ローカルモデル（例: Whisper CPU / GPU）
  * クラウド API（例: 任意の STT サービス）
* 同期 / 非同期呼び出しを統一的に扱えるよう設計
* エラー種別をモデルごとにラップして共通型で返す

### 6.4 テキスト表示と編集

* STT 結果をテキストエリアに表示
* ユーザーが軽く編集できる（Backspace, 矢印キーなど）
* `Enter` で挿入、`Shift+Enter` で改行のみの挙動も検討

### 6.5 テキスト挿入

* フロントのアプリ・ウィンドウ・フォーカス要素を特定
* 可能ならアクセシビリティ API でブラウザやネイティブテキストフィールドに直接挿入
* 難しい場合のフォールバック

  * クリップボードにテキストを一時保存
  * `Cmd+V` を合成キーとして送信
  * 元のクリップボード内容を復元

### 6.6 モデル切り替え / 設定

* `Preferences` ウィンドウ

  * 登録済みモデル一覧
  * モデル追加・編集・削除
  * デフォルトモデルの選択
* モデルごとの設定

  * 表示名
  * バックエンド種別（`local`, `cloud` など）
  * エンドポイント URL / モデル名
  * API キー / 認証情報
  * 言語設定（`auto`, `ja`, `en`, ...）

### 6.7 起動・常駐

* ログイン時自動起動（オプション）
* メニューバーアイコン

  * 現在のステータス表示（Idle / Recording / Error）
  * メニューから設定 / Quit / モデル切り替え

---

## 7. Non-Functional Requirements

### 7.1 パフォーマンス

* ショートカット押下 → ウィンドウ表示まで 150ms 以内を目標
* 録音停止 → 初回テキスト出力まで

  * ローカルモデル: 2–3秒以内（短文）
  * クラウドモデル: ネットワーク次第だが 1–5秒を目標
* CPU/GPU 使用率が常時高負荷にならないように（バックグラウンドモデルの扱いに注意）

### 7.2 信頼性

* STT サービスが落ちている / タイムアウトした場合

  * ユーザーにわかりやすいエラー
  * 可能であれば別モデルへのフェイルオーバー（将来対応）
* 異常終了しても macOS 再ログイン時に自動再起動

### 7.3 プライバシー・セキュリティ

* 音声/テキストのログ保存ポリシー

  * デフォルトでは保存しない or 短時間だけメモリ保持
  * ローカルログ保存はオプトイン
* クラウド STT 利用時

  * どのサービスに音声が送られるか明示
  * API キーは macOS Keychain に保存
* アクセシビリティ権限 / マイク権限の取得と UI 上の説明

### 7.4 アクセシビリティ

* VoiceOver での操作が可能
* キーボードのみで完結したフロー（マウス不要）

### 7.5 多言語対応

* UI は英語 / 日本語のローカライズ（将来拡張）
* STT 言語と UI 言語は独立して選択可能

---

## 8. Architecture

### 8.1 コンポーネント概要

* `AppDelegate / SceneDelegate`

  * アプリライフサイクル管理
  * 起動時の初期化
* `HotkeyManager`

  * グローバルショートカット登録・検知
* `OverlayWindowController`

  * オーバーレイウィンドウの表示 / 非表示
  * 状態管理（Ready, Recording, Transcribing, Preview...）
* `AudioEngine`

  * マイク入力取得
  * バッファ管理 / フォーマット変換
* `STTEngine`

  * STT バックエンドへの共通インタフェース
* `STTModelProvider` 実装群

  * `LocalWhisperProvider`
  * `CloudAPIProvider`（複数のサービスをサポートできるように）
* `TextInsertionService`

  * フロントアプリへのテキスト挿入ロジック
* `SettingsStore`

  * 設定値の永続化（UserDefaults + Keychain）
* `LogService`

  * イベントログ・エラーログの管理

### 8.2 データフロー（シーケンス）

1. `HotkeyManager` がショートカット検知
2. `OverlayWindowController` に通知 → ウィンドウ表示
3. `OverlayWindowController` が `AudioEngine` に録音開始を指示
4. `AudioEngine` が音声バッファを収集
5. 録音終了イベント（ユーザー操作 or 自動タイムアウト）
6. `OverlayWindowController` が `STTEngine` に音声データを渡す
7. `STTEngine` がアクティブな `STTModelProvider` を呼び出し
8. Provider が STT 実行 → テキスト結果 / エラーを返却
9. `OverlayWindowController` がテキスト結果をプレビューに表示
10. ユーザーが Enter を押すと `TextInsertionService` を呼び出し
11. テキスト挿入後、ウィンドウを閉じ、状態を Idle に戻す

---

## 9. STT Model Abstraction

### 9.1 Interface (Swift っぽい疑似コード)

```swift
protocol STTModelProvider {
    var id: String { get }            // internal identifier
    var displayName: String { get }   // UI用表示名
    var supportsStreaming: Bool { get }

    func transcribe(
        audioData: Data,
        language: String?,
        onPartialResult: ((String) -> Void)?,
        completion: @escaping (Result<String, STTError>) -> Void
    )
}

enum STTError: Error {
    case networkError
    case unauthorized
    case rateLimited
    case invalidResponse
    case internalError(String)
}
```

### 9.2 モデル設定構造

```swift
struct STTModelConfig: Codable {
    var id: String
    var displayName: String
    var backendType: BackendType
    var endpoint: URL?
    var apiKeyRef: String?  // Keychain key
    var defaultLanguage: String? // "auto", "ja", "en", ...
    var extraParams: [String: String] // backend-specific
}

enum BackendType: String, Codable {
    case localWhisper
    case cloudGeneric
    // 将来拡張用
}
```

* `SettingsStore` が `STTModelConfig` の配列を永続化
* `STTEngine` はアクティブモデルの `STTModelConfig` を参照して適切な Provider を生成/選択

---

## 10. macOS Integration

### 10.1 グローバルショートカット

* 候補 API

  * `Event Tap` (CGEventTap)
  * 既存ライブラリ（例: MASShortcut 相当の実装を自前/OSSで）
* ショートカット変更時に一度登録解除 → 再登録

### 10.2 フロントアプリ特定

* `NSWorkspace.shared.frontmostApplication`
* 必要に応じて `AXUIElement` を使ってフォーカス要素を取得

### 10.3 テキスト挿入戦略

1. **理想的パス**

   * アクセシビリティ API で対象テキストフィールドの `AXValue` を取得・更新
   * カーソル位置を考慮した挿入（将来的な高度機能）

2. **フォールバックパス**

   * 現在のクリップボード内容を退避
   * クリップボードに挿入テキストをセット
   * `Cmd+V` キーイベントを合成して送る
   * クリップボードを元に戻す

### 10.4 権限

* マイク使用許可

  * 初回録音時にシステムダイアログ
* アクセシビリティ許可

  * テキスト挿入のために必要
  * 権限が無い場合は設定画面を開く誘導 UI

---

## 11. Error Handling & Edge Cases

* **マイク権限がない**

  * ユーザーに権限付与を促す画面
  * システムの設定アプリへのショートカット
* **アクセシビリティ権限がない**

  * テキスト挿入に失敗した場合に通知
  * クリップボードコピーだけ行うモードに自動フォールバックも検討
* **ネットワークエラー（クラウドモデル）**

  * `STTError.networkError` にマッピング
  * モデル名付きでエラーメッセージ表示
* **タイムアウト**

  * 一定時間応答がない場合はキャンセルしてエラー表示
* **長文すぎる / 制限超過**

  * 録音時に上限時間を設定し、超えたら自動停止
* **前面アプリがテキスト入力不可**

  * クリップボード挿入すらできない場合は「クリップボードにコピーしました」と通知して終了

---

## 12. Configuration & Extensibility

* モデルの追加は UI から行えるが、裏側では JSON 定義として保存
* （将来）設定ファイルを外部から読み込んで自動登録する機能も検討
* `STTModelProvider` を新規追加するだけで新しい STT サービスを統合できるようにする

---

## 13. Technology Choices

* 言語: **Swift**
* UI: **SwiftUI + 一部 AppKit ブリッジ**

  * オーバーレイウィンドウ / メニューバーアプリは AppKit と相性が良い
* サポート OS バージョン: macOS 13 Ventura 以降（仮）
* 依存ライブラリ（候補）

  * 音声処理: AVFoundation
  * ショートカット: 自前 or 小さな OSS ライブラリ
  * ローカル STT: Whisper ラッパー or 既存バインディングを活用（要検討）

---

## 14. Distribution & Installation

### 14.1 Homebrew Cask（推奨）

uguisu は Homebrew Cask 経由でインストール可能にする。

```bash
# インストール
brew install --cask uguisu

# アップグレード
brew upgrade --cask uguisu

# アンインストール
brew uninstall --cask uguisu
```

#### Cask 定義（homebrew-cask への PR 用）

```ruby
cask "uguisu" do
  version "1.0.0"
  sha256 "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

  url "https://github.com/s4na/uguisu/releases/download/v#{version}/uguisu-#{version}.dmg"
  name "uguisu"
  desc "macOS voice shortcut input app - speak and type anywhere"
  homepage "https://github.com/s4na/uguisu"

  app "uguisu.app"

  zap trash: [
    "~/Library/Application Support/uguisu",
    "~/Library/Preferences/com.s4na.uguisu.plist",
    "~/Library/Caches/com.s4na.uguisu",
  ]
end
```

#### 自前 Tap の運用（初期リリース用）

公式 homebrew-cask にマージされるまでは、自前の Tap で配布:

```bash
# Tap を追加
brew tap s4na/tap

# インストール
brew install --cask s4na/tap/uguisu
```

Tap リポジトリ構成:
```
s4na/homebrew-tap/
├── Casks/
│   └── uguisu.rb
└── README.md
```

### 14.2 GitHub Releases

* リリースごとに以下のアセットを添付:
  * `uguisu-<version>.dmg` - ディスクイメージ（ドラッグ&ドロップインストール用）
  * `uguisu-<version>.zip` - 圧縮アーカイブ
  * `uguisu-<version>.pkg` - インストーラパッケージ（オプション）
* すべてのバイナリは Apple Developer ID で署名 & notarization 済み

### 14.3 ビルド & リリースパイプライン

GitHub Actions でリリースを自動化:

1. タグ `v*` がプッシュされたらワークフロー起動
2. `xcodebuild` でアプリをビルド（Release 構成）
3. `codesign` で署名
4. `notarytool` で notarization 実行
5. DMG / ZIP を作成
6. GitHub Release を作成し、アセットをアップロード
7. Homebrew Tap の Cask 定義を自動更新（SHA256 とバージョン）

### 14.4 署名 & Notarization

* **必須**: Apple Developer Program への登録（年間 $99）
* **Developer ID Application** 証明書でアプリに署名
* **Notarization** で Apple のマルウェアチェックを通過
* Gatekeeper でブロックされずにインストール可能

### 14.5 システム要件

* macOS 13 Ventura 以降
* Apple Silicon (M1/M2/M3) および Intel Mac 対応（Universal Binary）
* マイクアクセス権限
* アクセシビリティ権限（テキスト挿入用）

---

## 15. Security Considerations

### 15.1 クリップボード操作のセキュリティ

クリップボードフォールバック使用時のリスクと対策:

* **リスク**:
  * 他アプリが同時にクリップボードにアクセスした場合のレースコンディション
  * クリップボード履歴ツールによる機密データの露出
  * 復元失敗時に音声テキストがクリップボードに残る

* **対策**:
  ```swift
  class ClipboardManager {
      private let lock = NSLock()

      func insertWithClipboard(_ text: String) {
          lock.lock()
          defer { lock.unlock() }

          let pasteboard = NSPasteboard.general
          let originalContents = pasteboard.string(forType: .string)

          pasteboard.clearContents()
          pasteboard.setString(text, forType: .string)

          // Cmd+V を送信
          sendPasteKeystroke()

          // ペースト完了を待機（100ms）
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              pasteboard.clearContents()
              if let original = originalContents {
                  pasteboard.setString(original, forType: .string)
              }
          }
      }
  }
  ```
  * アトミックな操作のためロックを使用
  * ペースト完了を確認してから復元
  * 失敗時はユーザーに「クリップボードが上書きされました」と通知

### 15.2 API キー管理

* **Keychain 保存設定**:
  * `kSecAttrAccessibleWhenUnlocked` でロック解除時のみアクセス可能
  * アプリ固有のアクセスグループを使用
  * キー追加時にバリデーション（空文字・無効形式の検出）

* **キーローテーション**:
  * キー更新時は古いキーを安全に削除
  * 削除前にゼロフィルでメモリをクリア

* **環境変数サポート**（上級者向け）:
  ```swift
  func getAPIKey(for modelId: String) -> String? {
      // 1. 環境変数を優先（CI/開発環境用）
      if let envKey = ProcessInfo.processInfo.environment["UGUISU_API_KEY_\(modelId)"] {
          return envKey
      }
      // 2. Keychain から取得
      return KeychainManager.shared.getKey(for: modelId)
  }
  ```

### 15.3 音声データのライフサイクル

* **メモリ管理**:
  * 音声バッファは変換完了後即座にゼロフィル & 解放
  * `defer` ブロックでエラー時も確実にクリーンアップ
  * swap/core dump への漏洩防止のため一時ファイルは作成しない

* **データ保持ポリシー**:
  | 状態 | 音声データ | テキストデータ |
  |------|-----------|---------------|
  | 録音中 | メモリ保持 | - |
  | 変換中 | メモリ保持 | - |
  | プレビュー | 即時解放 | メモリ保持 |
  | 挿入完了 | - | 即時解放 |
  | エラー | 即時解放 | 即時解放 |

### 15.4 ネットワークセキュリティ

* HTTPS 必須（HTTP エンドポイントは拒否）
* 証明書ピニングの検討（主要クラウド STT サービス向け）
* リクエストレート制限（1秒あたり最大10リクエスト）
* 指数バックオフによるリトライ（最大3回）

### 15.5 テキスト挿入のセキュリティ

* **ターミナル検出**: ターミナルアプリへの挿入時は警告を表示
* **特殊文字エスケープ**: オプションで有効化可能なセーフモード
* **アクセシビリティ API の最小権限**: フォーカス中のテキストフィールドのみ操作

---

## 16. Error Recovery & Concurrency

### 16.1 状態遷移のスレッドセーフティ

```swift
actor AppStateManager {
    private(set) var currentState: AppState = .idle

    func transition(to newState: AppState) throws {
        guard isValidTransition(from: currentState, to: newState) else {
            throw StateError.invalidTransition(from: currentState, to: newState)
        }
        currentState = newState
    }

    private func isValidTransition(from: AppState, to: AppState) -> Bool {
        // 有効な遷移のみ許可
        switch (from, to) {
        case (.idle, .overlayOpening),
             (.overlayOpening, .ready),
             (.ready, .recording), (.ready, .closing),
             (.recording, .transcribing), (.recording, .closing),
             (.transcribing, .preview), (.transcribing, .error),
             (.preview, .insertAndClose), (.preview, .closing),
             (.insertAndClose, .idle), (.insertAndClose, .error),
             (.error, .idle),
             (.closing, .idle):
            return true
        default:
            return false
        }
    }
}
```

### 16.2 レースコンディション対策

| シナリオ | 問題 | 対策 |
|---------|------|------|
| 変換中に Esc | 変換結果が後から到着 | 状態チェック後に結果を破棄 |
| 連続ショートカット | 複数ウィンドウが開く | 500ms デバウンス + 状態チェック |
| 挿入中にアプリ切替 | 別アプリに挿入される | 挿入前にターゲットアプリを再確認 |
| クリップボード競合 | データ損失 | ロック + 遅延復元 |

### 16.3 エラーリカバリー戦略

```swift
enum RetryStrategy {
    case immediate
    case exponentialBackoff(baseDelay: TimeInterval, maxRetries: Int)
    case noRetry
}

extension STTError {
    var retryStrategy: RetryStrategy {
        switch self {
        case .networkError:
            return .exponentialBackoff(baseDelay: 1.0, maxRetries: 3)
        case .rateLimited:
            return .exponentialBackoff(baseDelay: 5.0, maxRetries: 2)
        case .unauthorized, .invalidResponse:
            return .noRetry
        case .internalError:
            return .immediate // 1回だけリトライ
        }
    }
}
```

### 16.4 グレースフルデグラデーション

1. **クラウド STT 失敗時**: ローカルモデルへの自動フォールバック（設定で有効化）
2. **アクセシビリティ API 失敗時**: クリップボード方式へフォールバック
3. **クリップボード復元失敗時**: 「クリップボードにコピーしました」通知で終了
4. **マイク切断時**: 録音済みデータを保持し、再接続を促す

### 16.5 フォーカス管理

```swift
class FocusManager {
    private var targetApp: NSRunningApplication?
    private var targetElement: AXUIElement?

    func captureCurrentFocus() {
        targetApp = NSWorkspace.shared.frontmostApplication
        targetElement = AXUIElementCreateSystemWide()
        // フォーカス要素を取得・保存
    }

    func restoreAndInsert(_ text: String) -> Bool {
        guard let app = targetApp else { return false }

        // ターゲットアプリがまだ存在するか確認
        guard app.isTerminated == false else {
            return fallbackToClipboard(text)
        }

        // ターゲットアプリをアクティブ化
        guard app.activate(options: .activateIgnoringOtherApps) else {
            return fallbackToClipboard(text)
        }

        // 少し待ってから挿入
        usleep(50_000) // 50ms
        return insertText(text, to: targetElement)
    }
}
```

---

## 17. Performance & Threading Model

### 17.1 スレッディングアーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                        Main Thread                          │
│  • UI 更新                                                  │
│  • ユーザー入力処理                                          │
│  • 状態遷移の発火                                            │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  Audio Queue  │   │   STT Queue   │   │  I/O Queue    │
│  (High Pri)   │   │  (Default)    │   │  (Utility)    │
│               │   │               │   │               │
│ • 録音処理    │   │ • 音声変換    │   │ • Keychain    │
│ • バッファ    │   │ • API 呼び出し │   │ • 設定保存    │
└───────────────┘   └───────────────┘   └───────────────┘
```

### 17.2 パフォーマンス目標と計測

| メトリクス | 目標 | 計測方法 |
|-----------|------|----------|
| ショートカット → ウィンドウ表示 | < 150ms | `os_signpost` |
| 録音停止 → 変換開始 | < 50ms | `os_signpost` |
| ローカル STT（10秒音声） | < 3s | `os_signpost` |
| アイドル時 CPU 使用率 | < 0.5% | Instruments |
| アイドル時メモリ | < 50MB | Instruments |
| 録音中メモリ増加 | < 10MB/分 | Instruments |

### 17.3 メモリ管理

* **モデルのロード戦略**:
  * デフォルトモデル: 起動時にプリロード
  * 非デフォルトモデル: 初回使用時に遅延ロード
  * 非アクティブモデル: 5分後にアンロード

* **メモリ使用量の目安**:
  | コンポーネント | メモリ |
  |---------------|--------|
  | ベースアプリ | ~30MB |
  | Whisper tiny | ~150MB |
  | Whisper base | ~300MB |
  | Whisper small | ~500MB |

* **メモリプレッシャー対応**:
  ```swift
  DispatchSource.makeMemoryPressureSource(eventMask: .warning, queue: .main)
      .setEventHandler {
          STTEngine.shared.unloadInactiveModels()
      }
  ```

### 17.4 バッテリー最適化

* **電源状態の監視**:
  * バッテリー駆動時: GPU 使用を控え CPU のみで処理
  * 低電力モード時: クラウド STT を推奨
  * 充電中: フルパフォーマンス

* **App Nap 対応**:
  * アイドル時は App Nap を許可
  * ショートカット監視のみ維持

### 17.5 オーバーレイウィンドウの最適化

* バックグラウンドでウィンドウを非表示状態で事前作成
* ウィンドウ表示時はアニメーションを最小化
* SwiftUI の `drawingGroup()` で描画を最適化

---

## 18. Testing Strategy

### 18.1 ユニットテスト

**目標カバレッジ**: 80%以上

```swift
// テスト対象と方針
class STTEngineTests: XCTestCase {
    func testTranscriptionSuccess() {
        let mockProvider = MockSTTProvider(result: .success("こんにちは"))
        let engine = STTEngine(provider: mockProvider)

        let expectation = expectation(description: "transcription")
        engine.transcribe(audioData: testAudioData) { result in
            XCTAssertEqual(try? result.get(), "こんにちは")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testTranscriptionNetworkError() {
        let mockProvider = MockSTTProvider(result: .failure(.networkError))
        // エラーハンドリングのテスト
    }
}

class AppStateManagerTests: XCTestCase {
    func testValidStateTransitions() {
        // すべての有効な遷移をテスト
    }

    func testInvalidStateTransitions() {
        // 無効な遷移が拒否されることをテスト
    }
}

class ClipboardManagerTests: XCTestCase {
    func testClipboardRestoration() {
        // クリップボードの保存・復元をテスト
    }
}
```

### 18.2 インテグレーションテスト

```swift
class EndToEndTests: XCTestCase {
    func testFullFlow_HotkeyToInsertion() {
        // ショートカット → 録音 → 変換 → 挿入の全フロー
    }

    func testModelSwitchingDuringIdle() {
        // モデル切り替えの動作確認
    }

    func testPermissionDeniedFlow() {
        // 権限拒否時のフロー
    }

    func testErrorRecoveryFlow() {
        // エラー発生 → リトライ → 成功
    }
}
```

### 18.3 UI テスト

```swift
class OverlayWindowUITests: XCTestCase {
    func testOverlayAppearance() {
        // ウィンドウの表示・非表示
    }

    func testKeyboardNavigation() {
        // キーボードのみでの操作
    }

    func testVoiceOverAccessibility() {
        // VoiceOver 対応
    }
}
```

### 18.4 互換性テストマトリクス

| アプリ | AX API | クリップボード | 確認済み |
|--------|--------|---------------|---------|
| Safari | ✓ | ✓ | - |
| Chrome | ✓ | ✓ | - |
| VSCode | ? | ✓ | - |
| Terminal | - | ✓ | - |
| Slack | ✓ | ✓ | - |
| Notion | ? | ✓ | - |
| IntelliJ | ? | ✓ | - |

### 18.5 パフォーマンステスト

* **レイテンシ計測**: 各操作の応答時間を CI で自動計測
* **メモリリーク検出**: 長時間実行テスト（24時間）
* **負荷テスト**: 連続100回のショートカット発火

### 18.6 セキュリティテスト

* クリップボードレースコンディションの再現テスト
* Keychain アクセス権限のテスト
* ネットワーク傍受テスト（HTTPS 検証）
* 音声バッファのメモリクリア確認

### 18.7 CI/CD パイプライン

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild build -scheme uguisu
      - name: Unit Tests
        run: xcodebuild test -scheme uguisu -destination 'platform=macOS'
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
```

---

## 19. Open Questions / TODO

1. **STT モデルの具体的な候補**

   * ローカル: Whisper (C++ / Metal / CoreML など)
   * クラウド: どの STT サービスをサポートするか
2. **ストリーミング v.s. 一括変換**

   * どのモデルがストリーミング対応か
   * UI/UX と実装コストのバランス
3. **テキスト挿入の互換性調査**

   * ブラウザ、VSCode、IntelliJ、Slack、Notion 等での挙動
4. **ログとデバッグ**

   * どこまで詳細ログを持つか（プライバシーとのバランス）
5. **ライセンス**

   * ローカル STT ライブラリや依存 OSS のライセンス確認
6. **Homebrew 公式 Cask への登録**

   * 一定のユーザー数・スター数が必要（目安: 30+ stars, 30+ forks, or 75+ watchers）
   * 初期は自前 Tap で運用し、条件を満たしたら公式へ PR

---

もしこの `design.md` に「もう少しここを細かく書いてほしい」「シーケンス図・クラス図っぽく書きたい」などあれば、そのまま追記できるようにセクション増やしていく形でリファインしていこう。
