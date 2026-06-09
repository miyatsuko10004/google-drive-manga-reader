# Technology Steering

## 主要なスタック
- **プラットフォーム**: iOS 17.0+ (Swift 5.9+, SwiftUI)
- **ビルドシステム / プロジェクト定義**: XcodeGen (Xcode 15.0+)
- **依存関係管理**: Swift Package Manager (SPM)

## 主要ライブラリ
- **GoogleSignIn-iOS**: Googleアカウント認証（OAuth）
- **GoogleAPIClientForREST (Drive)**: Google Drive API操作（ファイル一覧・メタデータ・ダウンロード）
- **ZIPFoundation**: コミックアーカイブ（ZIP / CBZ）の解凍
- **Kingfisher**: カバー画像等のキャッシュおよび非同期画像ロード

## アーキテクチャ & 設計パターン
- **設計スタイル**: SwiftUIフレンドリーなMVVM/単一方向データフロー風パターン。
- **状態管理**: iOS 17+ の `@Observable` マクロを使用。Environmentを介して状態をViewに伝搬する。
  - ルートViewでインスタンスを保持し、`.environment()` で子Viewに注入する。
- **非同期処理**: Swift Concurrency (`async`/`await`, `task` modifier, `@MainActor`) を全面的に使用し、従来のGCDやDelegateパターンを置き換えている。

## 開発ルール & プラクティス
1. **XcodeGen ファースト**: `*.xcodeproj` は直接編集しない。パッケージ追加、ファイル構成の変更、ビルド設定の調整は `project.yml` を編集し、`xcodegen` コマンドで再生成する。
2. **秘密情報の管理**: APIクライアントIDなどの機密情報は `Secrets.xcconfig`（Git管理外）で管理し、プロジェクト設定に反映させる。コミットに含めない。
3. **エラーハンドリング**: ユーザーアクションエラーはViewModel側でメッセージ（例: `errorMessage`）に落とし込み、View側で適切にトースト表示やアラートで可視化する。
