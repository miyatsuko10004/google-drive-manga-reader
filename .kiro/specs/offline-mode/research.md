# Research Log: offline-mode

## Summary
不安定なネットワーク環境での読み込み遅延や、完全なオフライン環境での起動に対応するため、オフラインモードの設計に向けた調査を実施しました。既存の `LocalStorageService` や `ComicSource` との統合方法、および Google サインイン認証のバイパス設計が主な論点です。

## Research Log

### Topic 1: Googleサインインのタイムアウトとバイパス
- **Source**: `AuthViewModel.swift`, `GD_MangaReaderApp.swift`
- **Findings**:
  - `AuthViewModel.restorePreviousSignIn()` が起動時に走り、成功すると `isSignedIn` が true になりますが、オフライン時は通信エラーとなりログイン画面（`LoginView`）でスタックします。
- **Implications**:
  - アプリ全体でオフラインを扱うため、`isOfflineMode` フラグを `AuthViewModel`（または共有設定）で管理し、`UserDefaults` で永続化します。これにより、未サインイン時やオフライン起動時でも、認証状態をバイパスして直接 `LibraryView` へ遷移可能にします。

### Topic 2: ローカルコミックと既存リスト表示（DriveItem）の統合
- **Source**: `LibraryViewModel.swift`, `DriveItem.swift`, `LocalComic.swift`
- **Findings**:
  - ライブラリ一覧は `[DriveItem]` 型の配列で保持されており、ソートやフィルタもこれに依存しています。
- **Implications**:
  - `LocalComic` を `DriveItem` にマッピングする拡張メソッド/イニシャライザを定義します。これにより、オフラインモード時に `LibraryViewModel.items` をローカルデータで差し替えるだけで、既存のグリッド表示や検索機能を修正せずに再利用できます。

---

## Architecture Pattern Evaluation

### 検討されたオプション
1. **オプション A（LibraryView限定オフライン）**: ログイン完了後にのみライブラリ内でオフライン表示を切り替える。
2. **オプション B（グローバル認証バイパスオフライン - 採用）**: 起動時ログインをバイパスし、完全オフライン対応にする。

### 採用理由
ユーザーがネットワークのない状況（飛行機や地下等）でアプリを起動した場合に、ログイン画面でブロックされるのを防ぐため、オプション B を採用しました。

---

## Identified Risks & Mitigation

1. **オフライントグルの同期と画面遷移**
   - **リスク**: ライブラリ画面内でオフラインモードを OFF にした際、もしユーザーの Google サインインセッションが切れていると、予期せずログイン画面に強制遷移することになります。
   - **対策**: オフライン解除時にサインイン状態を確認し、未ログインの場合は警告アラート等を表示して、明示的にサインインフローへ誘導します。

2. **ローカルサムネイルの Kingfisher 読み込み**
   - **リスク**: `KFImage` は通常リモート URL を想定していますが、ローカルファイルパス (`file:///...`) も処理可能です。ただし、キャッシュキー競合や画像未検出のエラーハンドリングが必要です。
   - **対策**: `LocalComic` の `absolutePath` から生成したFileURLを正しく設定し、存在チェックを行います。
