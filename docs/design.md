# EchoType – macOS Voice Shortcut Input App Design

> **Project Name**: `EchoType`
> **Tagline**: “Hit a shortcut, speak, hit Enter, text appears where you were typing.”

---

## 1. Overview

EchoType は、macOS 上でグローバルショートカットを押すと立ち上がる「一時的な音声入力ランチャー」です。

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
3. EchoType のオーバーレイウィンドウが表示される

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

## 14. Open Questions / TODO

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
6. **配布形態**

   * notarization / sandbox / App Store かどうか

---

もしこの `design.md` に「もう少しここを細かく書いてほしい」「シーケンス図・クラス図っぽく書きたい」などあれば、そのまま追記できるようにセクション増やしていく形でリファインしていこう。
