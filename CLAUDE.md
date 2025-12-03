* プログラム以外は日本語で書いて。
* gitでpushしたら、prタイトルとpr説明も更新して。
* mainブランチからブランチを切るときは、fetchした上で最新のmainブランチからブランチを切って。
* CLAUDE.local.md および CLAUDE.project.md が存在する場合、CLAUDE.md と同等の指示ファイルとして扱ってください。
* PRを作成したり、PRを更新した後は「PRの内容をサブエージェントにレビューさせる」のと「改善したほうがいいと90%以上確信したことについて対応する」のを3回繰り返してください。
* 実装したらテストコードも書いて

---
## 共通フォーマット

すべてのタイトル: `<type>: <subject>` (50文字以内)

type: feat | fix | docs | refactor | test | chore

---

## コミットメッセージ
```
<type>: <subject>

## User Request
<要望の1行要約>

## AI Reasoning
- 採用した手法と理由
- 却下した代替案（あれば）
```

---

## PR

タイトル: コミットと同形式
```
## Related Issue
Closes #<番号>

## User Request / AI Reasoning
（コミットメッセージと同様、全体を通した判断を記載）

## Changes
- 主な変更点

## Verification
- [ ] テスト / 動作確認
```

---

## Issue
```
## Context
<現状の課題>

## Goal
<達成したい状態>

## Proposed Solution
- アプローチ概要

## Done条件
- [ ] 要件
```
