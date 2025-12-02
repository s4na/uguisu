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
  * **最大録音時間: 60秒**（ハードリミット）
  * 60秒に達した場合: 自動的に録音を停止し、変換処理を開始
  * 残り10秒時点でUIに警告表示
* 高度な編集機能（Markdown プレビューやエディタ機能）は持たない
* 独自の STT モデル学習・ファインチューニング機能の実装

---

## 4. User Stories

1. **US-01: ショートカットから即音声入力**

   * 「テキストエディタで文章を書いているとき、ショートカットを押すだけで音声入力ウィンドウが開き、話し終わって Enter でテキストが挿入されてほしい。」

2. **US-02: モデル切り替え**

   * 「精度やレイテンシ、コストに応じて `Whisper-local` と `Cloud-STT` を切り替えたい。」

3. **US-03: 変換結果のプレビュー**

   * **US-03a: ストリーミング対応モデルの場合**
     * 「しゃべっている途中から、リアルタイムでテキストが見えると安心できる。」
     * `supportsStreaming: true` のモデルで有効
   * **US-03b: ストリーミング非対応モデルの場合**
     * 「処理中...」インジケータ（スピナー + 経過時間）を表示
     * 変換完了後にテキストを一括表示

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
2. グローバルショートカット（デフォルト: `⌥ + Space`）を押す
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

### 5.3 状態遷移

```
┌─────────────────────────────────────────────────────────────────────┐
│  Idle ──[shortcut]──► OverlayOpening ──[animation done]──► Ready   │
│    ▲                                                          │    │
│    │                           ┌──────────────────────────────┘    │
│    │                           ▼                                   │
│    │    ┌─────────── ModelLoading ◄──[lazy load needed]           │
│    │    │                  │                                       │
│    │    │ [load complete]  │ [load error]                         │
│    │    ▼                  ▼                                       │
│    │  Ready ◄───────── Error                                      │
│    │    │                  ▲                                       │
│    │    │ [Space/auto]     │                                       │
│    │    ▼                  │                                       │
│    │  Recording ──[timeout:60s]──► Transcribing                   │
│    │    │                              │                           │
│    │    │ [Esc]                        │ [STT error]              │
│    │    ▼                              ▼                           │
│    │  Closing                       Retrying ──[max retries]──►   │
│    │    │                              │                           │
│    │    │                   [success]  │                           │
│    │    │                       ┌──────┘                           │
│    │    │                       ▼                                  │
│    │    │                    Preview                               │
│    │    │                       │                                  │
│    │    │            [Enter]    │    [Esc]                        │
│    │    │               ▼       │      ▼                          │
│    │    │         InsertAndClose│   Closing                       │
│    │    │               │       │      │                          │
│    └────┴───────────────┴───────┴──────┘                          │
└─────────────────────────────────────────────────────────────────────┘
```

#### 状態詳細

| 状態 | 説明 | 遷移条件 |
|------|------|----------|
| `Idle` | 常駐・メニューバーアイコンのみ | ショートカット押下 → `OverlayOpening` |
| `OverlayOpening` | ウィンドウ表示アニメーション中 | アニメーション完了（~50ms）→ `Ready` or `ModelLoading` |
| `ModelLoading` | 遅延ロードモデルの読み込み中 | ロード完了 → `Ready`、エラー → `Error` |
| `Ready` | 録音待機状態 | `Space` or auto-start → `Recording`、`Esc` → `Closing` |
| `Recording` | 録音中 | `Space` or タイムアウト（60秒）→ `Transcribing`、`Esc` → `Closing` |
| `Transcribing` | STT 変換中 | 成功 → `Preview`、エラー → `Retrying` or `Error` |
| `Retrying` | リトライ中（指数バックオフ） | 成功 → `Preview`、最大リトライ超過 → `Error` |
| `Preview` | 変換結果表示・編集可能 | `Enter` → `InsertAndClose`、`Esc` → `Closing` |
| `InsertAndClose` | テキスト挿入処理中 | 成功 → `Idle`、失敗 → `Error`（ウィンドウは閉じる） |
| `Error` | エラー表示 | ユーザー確認（Enter/Esc）→ `Idle` |
| `Closing` | ウィンドウ閉じ中 | 完了 → `Idle` |

#### タイムアウト値

| 状態 | タイムアウト | 動作 |
|------|-------------|------|
| `Recording` | 60秒 | 自動停止 → `Transcribing` |
| `Transcribing` | 30秒 | タイムアウトエラー → `Retrying` |
| `Retrying` | 各リトライ: 1s, 2s, 4s（指数バックオフ） | 最大3回 → `Error` |
| `ModelLoading` | 10秒 | ロードタイムアウト → `Error` |

---

## 6. Functional Requirements

### 6.1 グローバルショートカット

* macOS のどのアプリ上でもショートカットを受け取れる
* 設定画面からショートカット変更可能
* ショートカットが既存アプリのショートカットと衝突した場合の考慮（可能なら検出）

#### デフォルトショートカット

**推奨: `⌥ Option + Space`**

| 候補 | 評価 | 備考 |
|------|------|------|
| `⌥ + Space` | ⭐⭐⭐ 推奨 | 片手で押しやすい、主要アプリと衝突少ない |
| `⌘⇧ + Space` | ⭐⭐ | Spotlight（`⌘ + Space`）と似ていて覚えやすいが、一部アプリで使用 |
| `⌃ + Space` | ⭐ | 入力ソース切替とデフォルトで衝突（macOS設定で変更可能） |
| `Fn + Fn`（ダブルタップ） | ⭐⭐ | macOS の音声入力と衝突する可能性 |
| `⌘⌥ + V` | ⭐⭐ | 「Voice」の V で覚えやすいが、両手が必要 |

**選定理由（`⌥ + Space`）**:
* **片手操作**: 左手だけで押せる（右手はマウス/トラックパッドに置いたまま）
* **衝突が少ない**: Spotlight（`⌘Space`）、入力切替（`⌃Space`）と異なる修飾キー
* **直感的**: Space = 音声 → スペース（話すスペース）のメタファー
* **Raycast/Alfred ユーザー**: `⌥Space` は比較的空いていることが多い

**注意**: ユーザーが別のアプリで `⌥Space` を使用している場合は、初回起動時に検出して代替を提案

### 6.2 音声録音

* システムのデフォルトマイクを利用
* サンプリング: 16kHz or 44.1kHz（モデルに合わせて変換）
* フォーマット: PCM (WAV) / その他モデル仕様に合わせる
* **録音時間の上限: 60秒**（ハードリミット、Section 3 参照）
  * 50秒経過時: UI に「残り10秒」警告表示
  * 60秒到達時: 自動停止 → `Transcribing` 状態へ遷移
* 録音中は視覚的フィードバック（波形 or レベルメーター + 経過時間表示）

### 6.3 STT モデル呼び出し

* 音声データを `STTEngine` 抽象インタフェースに渡す
* 同一インタフェースで複数バックエンドを扱う

  * ローカルモデル（例: Whisper CPU / GPU）
  * クラウド API（例: 任意の STT サービス）
* 同期 / 非同期呼び出しを統一的に扱えるよう設計
* エラー種別をモデルごとにラップして共通型で返す

#### ストリーミング vs 一括変換

モデルの `supportsStreaming` フラグに基づいて自動的に最適な方式を選択:

| モデル種別 | 方式 | UX |
|-----------|------|-----|
| ストリーミング対応 | リアルタイム変換 | 話しながらテキストが逐次表示 |
| 一括変換のみ | 録音完了後に変換 | 「処理中...」表示 → 完了後に一括表示 |
| 一括変換（長文） | チャンク分割変換 | 10秒ごとに分割して順次変換・表示 |

```swift
class STTEngine {
    func transcribe(audio: AudioBuffer, provider: STTModelProvider) async throws -> String {
        if provider.supportsStreaming {
            // ストリーミング対応: リアルタイム変換
            return try await streamingTranscribe(audio: audio, provider: provider)
        } else if audio.duration > 10.0 {
            // 長文の場合: 10秒チャンクで分割変換
            return try await chunkedTranscribe(audio: audio, provider: provider, chunkDuration: 10.0)
        } else {
            // 短文: 一括変換
            return try await batchTranscribe(audio: audio, provider: provider)
        }
    }

    private func chunkedTranscribe(audio: AudioBuffer, provider: STTModelProvider, chunkDuration: TimeInterval) async throws -> String {
        var results: [String] = []
        let chunks = audio.split(every: chunkDuration)

        for chunk in chunks {
            let text = try await provider.transcribe(audioData: chunk.data, language: nil, onPartialResult: nil)
            results.append(text)
            // チャンクごとに UI を更新（部分結果を表示）
            await MainActor.run { updatePartialResult(results.joined()) }
        }

        return results.joined()
    }
}
```

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

#### Event Tap と権限要件

**重要**: `CGEventTap` はアクセシビリティ権限が必要。権限がない場合は `nil` が返される。

```swift
class HotkeyManager {
    func setupEventTap() -> Bool {
        // 権限チェック
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            // 権限がない場合は設定画面を開く
            promptForAccessibilityPermission()
            return false
        }

        // Event Tap 作成
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: eventCallback,
            userInfo: nil
        ) else {
            // 権限があるのに失敗 = システムエラー
            Logger.shared.log(.error, "Failed to create event tap")
            return false
        }

        // Run loop に追加
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }
}
```

* **起動時の権限チェックフロー**:
  1. `AXIsProcessTrusted()` でアクセシビリティ権限を確認
  2. 権限がない場合: 説明ダイアログを表示 → システム環境設定を開く
  3. 権限付与後: Event Tap を登録
  4. 権限が拒否された場合: アプリの主要機能は使用不可と明示

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

### 12.1 設定ファイルのバージョニング

```swift
struct AppConfig: Codable {
    static let currentVersion = 2

    let version: Int
    let models: [STTModelConfig]
    let preferences: UserPreferences

    init() {
        self.version = Self.currentVersion
        self.models = []
        self.preferences = UserPreferences()
    }
}
```

### 12.2 マイグレーション戦略

設定ファイルのバージョンアップ時に破壊的変更を安全に処理:

```swift
class ConfigMigrator {
    static func migrate(from data: Data) throws -> AppConfig {
        let decoder = JSONDecoder()

        // まずバージョンのみを取得
        struct VersionOnly: Decodable { let version: Int? }
        let versionInfo = try decoder.decode(VersionOnly.self, from: data)
        let version = versionInfo.version ?? 1

        switch version {
        case 1:
            let v1 = try decoder.decode(AppConfigV1.self, from: data)
            return migrateV1toV2(v1)
        case 2:
            return try decoder.decode(AppConfig.self, from: data)
        default:
            throw ConfigError.unsupportedVersion(version)
        }
    }

    private static func migrateV1toV2(_ v1: AppConfigV1) -> AppConfig {
        // V1 → V2 のフィールドマッピング
        // 例: 古いフィールド名を新しい名前に変換
        return AppConfig(
            version: 2,
            models: v1.sttModels.map { convertModel($0) },
            preferences: convertPreferences(v1)
        )
    }
}
```

* **バックアップ**: マイグレーション前に自動バックアップを作成
* **ロールバック**: マイグレーション失敗時は元の設定を維持
* **ログ**: マイグレーションの成否をログに記録

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

#### Secrets 管理

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ['v*']

env:
  APPLE_DEVELOPER_ID: ${{ secrets.APPLE_DEVELOPER_ID }}
  APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  NOTARIZATION_APPLE_ID: ${{ secrets.NOTARIZATION_APPLE_ID }}
  NOTARIZATION_PASSWORD: ${{ secrets.NOTARIZATION_PASSWORD }}
  KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Install Certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          # 一時 Keychain を作成
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain

          # 証明書をインポート
          echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          security import certificate.p12 -k build.keychain \
            -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: \
            -s -k "$KEYCHAIN_PASSWORD" build.keychain

      - name: Build and Sign
        run: |
          xcodebuild archive -scheme uguisu -archivePath build/uguisu.xcarchive
          xcodebuild -exportArchive -archivePath build/uguisu.xcarchive \
            -exportPath build/export -exportOptionsPlist ExportOptions.plist

      - name: Notarize
        run: |
          xcrun notarytool submit build/export/uguisu.app.zip \
            --apple-id "$NOTARIZATION_APPLE_ID" \
            --password "$NOTARIZATION_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            build/uguisu-*.dmg
            build/uguisu-*.zip
```

**必要な Secrets**:
| Secret 名 | 説明 |
|-----------|------|
| `APPLE_DEVELOPER_ID` | Developer ID（例: `Developer ID Application: Name (TEAMID)`） |
| `APPLE_TEAM_ID` | Apple Team ID |
| `NOTARIZATION_APPLE_ID` | App Store Connect のメールアドレス |
| `NOTARIZATION_PASSWORD` | App-specific password |
| `APPLE_CERTIFICATE_BASE64` | .p12 証明書を base64 エンコードしたもの |
| `APPLE_CERTIFICATE_PASSWORD` | 証明書のパスワード |
| `KEYCHAIN_PASSWORD` | 一時 Keychain 用のパスワード |

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

### 14.6 自動アップデート

[Sparkle](https://sparkle-project.org/) フレームワークを使用した自動アップデート機能:

#### 基本設定

```swift
// AppDelegate.swift
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 自動アップデートチェックを有効化
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.updateCheckInterval = 86400 // 24時間
    }
}
```

#### Appcast フィード

```xml
<!-- https://example.com/appcast.xml -->
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>uguisu Updates</title>
    <item>
      <title>Version 1.1.0</title>
      <sparkle:version>1.1.0</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>Mon, 01 Jan 2025 12:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/s4na/uguisu/releases/download/v1.1.0/uguisu-1.1.0.dmg"
        sparkle:edSignature="..."
        length="12345678"
        type="application/octet-stream"/>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
          <li>New feature: ...</li>
          <li>Bug fix: ...</li>
        </ul>
      ]]></description>
    </item>
  </channel>
</rss>
```

#### アップデートポリシー

| 種別 | 動作 | ユーザー確認 |
|------|------|-------------|
| 通常アップデート | バックグラウンドでダウンロード、次回起動時に適用 | 必要 |
| セキュリティ修正 | 即時通知、強く推奨 | 必要（スキップ不可） |
| 緊急セキュリティ | 強制アップデート | 起動時にブロック |

```swift
// 強制アップデートの判定
extension SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldPostpone update: SUAppcastItem, until date: Date) -> Bool {
        // criticalUpdate フラグがある場合は延期不可
        if update.isCriticalUpdate {
            return false
        }
        return true
    }
}
```

#### リリースノート表示

* アップデート確認時にリリースノートを表示
* 日本語/英語のローカライズ対応
* 「今すぐ更新」「後で」「スキップ」のオプション

---

## 15. Security Considerations

### 15.1 クリップボード操作のセキュリティ

クリップボードフォールバック使用時のリスクと対策:

* **リスク**:
  * 他アプリが同時にクリップボードにアクセスした場合のレースコンディション
  * クリップボード履歴ツールによる機密データの露出
  * 復元失敗時に音声テキストがクリップボードに残る

* **対策**（Swift Concurrency 対応版）:
  ```swift
  actor ClipboardManager {
      private var isOperating = false

      func insertWithClipboard(_ text: String, to targetElement: AXUIElement?) async -> ClipboardResult {
          guard !isOperating else {
              return .busy
          }
          isOperating = true
          defer { isOperating = false }

          let pasteboard = NSPasteboard.general
          let originalContents = pasteboard.string(forType: .string)
          let originalLength = await getTextLength(of: targetElement)

          pasteboard.clearContents()
          pasteboard.setString(text, forType: .string)

          // Cmd+V を送信
          await sendPasteKeystroke()

          // ペースト完了を検証
          let pasteSucceeded = await waitForPasteCompletion(
              targetElement: targetElement,
              expectedLength: originalLength + text.count,
              timeout: 0.5
          )

          // クリップボード復元
          pasteboard.clearContents()
          if let original = originalContents {
              pasteboard.setString(original, forType: .string)
          }

          return pasteSucceeded ? .success : .pasteTimeout
      }

      /// ペースト完了をポーリングで検証
      private func waitForPasteCompletion(
          targetElement: AXUIElement?,
          expectedLength: Int,
          timeout: TimeInterval
      ) async -> Bool {
          let startTime = Date()
          let pollInterval: TimeInterval = 0.05 // 50ms

          while Date().timeIntervalSince(startTime) < timeout {
              let currentLength = await getTextLength(of: targetElement)
              if currentLength >= expectedLength {
                  return true
              }
              try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
          }
          return false
      }

      private func getTextLength(of element: AXUIElement?) async -> Int {
          guard let element = element else { return 0 }
          var value: CFTypeRef?
          let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
          guard result == .success, let str = value as? String else { return 0 }
          return str.count
      }
  }

  enum ClipboardResult {
      case success
      case busy
      case pasteTimeout
  }
  ```
  * **actor を使用**: Swift Concurrency との整合性、スレッドセーフな設計
  * **ペースト完了の検証**: テキスト長の変化をポーリングで検出
  * **タイムアウト**: 0.5秒で検証を打ち切り
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

* **一時ファイル**:
  * ディスク I/O を減らすため、**可能な限りオンメモリで処理**
  * 一時ファイルが必要な場合（大容量音声など）は暗号化して保存し、処理後即削除
  * `/tmp` や `NSTemporaryDirectory()` への書き込みは原則禁止

* **ログ出力の制限**（プライバシー保護）:
  ```swift
  // ❌ 絶対にログ出力しない
  Logger.log("Audio data: \(audioBuffer.data)")
  Logger.log("Transcribed text: \(result)")

  // ✅ 許可されるログ
  Logger.log("Recording started, duration: \(duration)s")
  Logger.log("Transcription completed, length: \(text.count) chars")
  Logger.log("STT model: \(modelName), latency: \(latency)ms")
  ```
  * デバッグログであっても、音声データそのものや変換後のテキスト内容は**絶対に出力しない**
  * 許可される情報: 処理時間、データ長、モデル名、エラーコード（内容は除く）

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
enum AppState: Equatable {
    case idle
    case overlayOpening
    case modelLoading      // 追加: 遅延ロード中
    case ready
    case recording
    case transcribing
    case retrying(attempt: Int)  // 追加: リトライ中
    case preview
    case insertAndClose
    case error(AppError)
    case closing
}

actor AppStateManager {
    private(set) var currentState: AppState = .idle

    func transition(to newState: AppState) throws {
        guard isValidTransition(from: currentState, to: newState) else {
            throw StateError.invalidTransition(from: currentState, to: newState)
        }
        currentState = newState
    }

    private func isValidTransition(from: AppState, to: AppState) -> Bool {
        // 有効な遷移のみ許可（Section 5.3 の状態遷移図と整合）
        switch (from, to) {
        case (.idle, .overlayOpening),
             // OverlayOpening からの遷移
             (.overlayOpening, .ready),
             (.overlayOpening, .modelLoading),
             // ModelLoading からの遷移
             (.modelLoading, .ready),
             (.modelLoading, .error),
             // Ready からの遷移
             (.ready, .recording),
             (.ready, .closing),
             // Recording からの遷移
             (.recording, .transcribing),
             (.recording, .closing),
             // Transcribing からの遷移
             (.transcribing, .preview),
             (.transcribing, .retrying),
             (.transcribing, .error),
             // Retrying からの遷移
             (.retrying, .preview),
             (.retrying, .error),
             // Preview からの遷移
             (.preview, .insertAndClose),
             (.preview, .closing),
             // InsertAndClose からの遷移
             (.insertAndClose, .idle),
             (.insertAndClose, .error),
             // Error/Closing からの遷移
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

### 16.5 オフラインモード

クラウド STT サービスが利用できない場合の動作:

```swift
class NetworkMonitor {
    private let monitor = NWPathMonitor()
    @Published var isOnline = true

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
}

class STTEngine {
    func selectBestAvailableModel() -> STTModelProvider {
        if !networkMonitor.isOnline {
            // オフライン時はローカルモデルのみ表示
            return getLocalModel() ?? showOfflineWarning()
        }
        return getPreferredModel()
    }
}
```

* **オフライン検出**:
  * `NWPathMonitor` でネットワーク状態を監視
  * クラウドモデル選択時にオフラインなら警告表示

* **オフライン時の動作**:
  | 状況 | 動作 |
  |------|------|
  | ローカルモデルあり | ローカルモデルを自動選択 |
  | ローカルモデルなし | 「オフラインです。ローカルモデルをインストールしてください」と表示 |
  | 録音中にオフライン化 | 録音を継続し、変換時にローカルモデルへフォールバック |

* **オフライン→オンライン復帰時**:
  * 自動的にクラウドモデルが利用可能に
  * 設定で「常にローカル優先」を選択可能

### 16.6 フォーカス管理

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

### 17.4 GPU 検出とフォールバック

```swift
class GPUCapabilityManager {
    enum GPUTier {
        case highPerformance  // 専用 GPU または M1 Pro/Max/Ultra
        case standard         // M1/M2 標準、Intel 統合 GPU
        case unavailable      // GPU アクセス不可
    }

    static func detectGPUTier() -> GPUTier {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return .unavailable
        }

        // Apple Silicon の高性能チップを検出
        if device.supportsFamily(.apple7) {
            // recommendedMaxWorkingSetSize で VRAM を推定
            let vram = device.recommendedMaxWorkingSetSize
            if vram >= 16 * 1024 * 1024 * 1024 { // 16GB+
                return .highPerformance
            }
        }
        return .standard
    }

    static func recommendedModel(for tier: GPUTier) -> String {
        switch tier {
        case .highPerformance:
            return "whisper-large"
        case .standard:
            return "whisper-base"
        case .unavailable:
            return "cloud-stt" // GPU なしはクラウド推奨
        }
    }
}
```

* **GPU 不可時の動作**:
  * 起動時に GPU 可用性を検出
  * GPU が使用不可の場合、ユーザーに通知し CPU モードまたはクラウド STT を推奨
  * Whisper モデルは CPU フォールバックを自動的に使用

### 17.5 バッテリー最適化

* **電源状態の監視**:
  * バッテリー駆動時: GPU 使用を控え CPU のみで処理
  * 低電力モード時: クラウド STT を推奨
  * 充電中: フルパフォーマンス

* **App Nap 対応**:
  * アイドル時は App Nap を許可
  * ショートカット監視のみ維持

### 17.6 オーバーレイウィンドウの最適化

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
  unit-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild build -scheme uguisu
      - name: Unit Tests
        run: xcodebuild test -scheme uguisu -destination 'platform=macOS'
      - name: Upload Coverage
        uses: codecov/codecov-action@v3

  ui-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: UI Tests
        run: xcodebuild test -scheme uguisu-UITests -destination 'platform=macOS'

  integration-test:
    needs: [unit-test]
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Integration Tests
        run: xcodebuild test -scheme uguisu-IntegrationTests -destination 'platform=macOS'
```

---

## 19. Logging & Diagnostics

### 19.1 ログレベルと出力

```swift
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

class Logger {
    static let shared = Logger()
    var minLevel: LogLevel = .info

    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function) {
        guard level >= minLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] [\(level)] \(function): \(message)"

        // os_log を使用（システムログに統合）
        os_log("%{public}@", log: .default, type: level.osLogType, entry)

        // デバッグビルドではコンソールにも出力
        #if DEBUG
        print(entry)
        #endif
    }
}
```

### 19.2 構造化ロギング

```swift
struct LogEvent: Codable {
    let timestamp: Date
    let level: String
    let category: String
    let message: String
    let metadata: [String: String]?

    // 音声データやテキストは絶対にログに含めない
}

enum LogCategory: String {
    case hotkey = "Hotkey"
    case audio = "Audio"
    case stt = "STT"
    case insertion = "Insertion"
    case ui = "UI"
    case error = "Error"
}
```

### 19.3 ユーザー向け診断画面

設定画面から「診断」タブでアクセス可能:

| 項目 | 表示内容 |
|------|----------|
| 最近の操作 | 直近10件の操作結果（成功/失敗） |
| モデル性能 | 各モデルの平均レイテンシ、成功率 |
| 権限状態 | マイク/アクセシビリティ権限の状態 |
| システム情報 | macOS バージョン、メモリ使用量 |

```swift
struct DiagnosticsView: View {
    @StateObject var diagnostics = DiagnosticsManager.shared

    var body: some View {
        List {
            Section("最近の操作") {
                ForEach(diagnostics.recentOperations) { op in
                    HStack {
                        Image(systemName: op.success ? "checkmark.circle" : "xmark.circle")
                            .foregroundColor(op.success ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(op.description)
                            Text(op.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("権限") {
                PermissionStatusRow(name: "マイク", status: diagnostics.micPermission)
                PermissionStatusRow(name: "アクセシビリティ", status: diagnostics.axPermission)
            }
        }
    }
}
```

### 19.4 診断情報のエクスポート

トラブルシューティング用に診断情報をエクスポート:

* **含める情報**:
  * アプリバージョン、macOS バージョン
  * 登録済みモデル一覧（API キーは除外）
  * エラーログ（直近100件）
  * パフォーマンスメトリクス

* **除外する情報**（プライバシー保護）:
  * 音声データ
  * 変換されたテキスト
  * API キー
  * 挿入先アプリの詳細

```swift
func exportDiagnostics() -> URL {
    let report = DiagnosticsReport(
        appVersion: Bundle.main.version,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        models: SettingsStore.shared.models.map { $0.sanitized },
        recentErrors: Logger.shared.recentErrors(limit: 100),
        metrics: PerformanceMetrics.shared.summary
    )

    let data = try! JSONEncoder().encode(report)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("uguisu-diagnostics-\(Date().timeIntervalSince1970).json")
    try! data.write(to: url)
    return url
}
```

---

## 20. Open Questions / TODO

1. **STT モデルの具体的な候補**

   * ローカル: Whisper (C++ / Metal / CoreML など)
   * クラウド: どの STT サービスをサポートするか
2. **ストリーミング v.s. 一括変換**

   * どのモデルがストリーミング対応か
   * UI/UX と実装コストのバランス
3. **テキスト挿入の互換性調査**

   * ブラウザ、VSCode、IntelliJ、Slack、Notion 等での挙動
4. **ライセンス**

   * ローカル STT ライブラリや依存 OSS のライセンス確認
5. **Homebrew 公式 Cask への登録**

   * 一定のユーザー数・スター数が必要（目安: 30+ stars, 30+ forks, or 75+ watchers）
   * 初期は自前 Tap で運用し、条件を満たしたら公式へ PR

---

もしこの `design.md` に「もう少しここを細かく書いてほしい」「シーケンス図・クラス図っぽく書きたい」などあれば、そのまま追記できるようにセクション増やしていく形でリファインしていこう。
