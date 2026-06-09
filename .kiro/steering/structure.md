# Structure Steering

## ディレクトリ構成パターン
本プロジェクトは、機能/役割ごとのレイヤード構造を採用しています。

```
GD-MangaReader/          # XcodeGen用ルートディレクトリ
├── project.yml          # XcodeGen プロジェクト定義ファイル
├── Secrets.xcconfig     # 機密設定 (Git対象外)
└── GD-MangaReader/      # ソースコードルート
    ├── App/             # アプリ起動エントリー、グローバル設定・定数
    ├── Models/          # ビジネスデータモデル (データ構造の定義)
    ├── Views/           # SwiftUI View (UIレイアウト)
    │   └── Components/  # 複数の画面で再利用されるUIパーツ
    ├── ViewModels/      # 各画面の状態管理およびビジネスロジック連携
    ├── Services/        # 外部API/OS機能ラッパー (Drive, 解凍, ローカルストレージ)
    ├── Modifiers/       # カスタムSwiftUI ViewModifier
    └── Resources/       # アセットカタログやPlistなど
```

## 命名規則とプラクティス
- **ファイル命名**:
  - View: `[Name]View.swift`
  - ViewModel: `[Name]ViewModel.swift`
  - Service: `[Name]Service.swift` （または `[Name]Manager.swift`）
  - Model: `[Name].swift`
- **インポート**: iOSプロジェクトであるため、Swift標準の `import` 文を使用する。不要なフレームワークのインポートは避ける。
- **グループ構造**: Xcode上の仮想グループ（Xcode Groups）と物理フォルダ構造を完全に一致させ、見通しを良くする（`createIntermediateGroups: true` で自動化）。

## 特記事項・注意点
- `project.yml` を編集した後は必ずターミナルで `xcodegen` を実行し、Xcodeプロジェクトファイルを更新すること。
- 不要または衝突する重複ファイルを防止する（例: `ToastView.swift` と `ToastView (1).swift` が見つかった場合は放置せずクリーンアップする）。
