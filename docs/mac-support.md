# Mac 対応（Designed for iPad）

Issue #47「Mac用アプリの開発（PC の大画面で読みたい）」への対応方針と手順をまとめる。

## 採用方式

方式 (B)「Designed for iPad」を採用する。iOS 版のバイナリを Apple Silicon の Mac 上でそのまま動かす方式で、コードやターゲットの追加は不要。

- `GD-MangaReader/project.yml` の `GD-MangaReader` ターゲットで `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: true` を明示している。
- 対象は **Apple Silicon の Mac のみ**（Intel Mac は非対応）。
- `TARGETED_DEVICE_FAMILY`、deploymentTarget、依存パッケージは変更していない。

## Xcode での実行手順

1. `GD-MangaReader` ディレクトリで `Secrets.xcconfig` を用意する（コミット対象外。ios.yml のダミー値でも起動確認は可能だが、Google ログインには実際の値が必要）。
2. `xcodegen generate` で `.xcodeproj` を生成し、Xcode で開く。
3. 実行先に **「My Mac (Designed for iPad)」** を選ぶ。
4. Signing & Capabilities で `DEVELOPMENT_TEAM`（自分のチーム）を設定して署名する。
5. Run する。

CLI でのビルド確認例:

```
xcodebuild build -scheme GD-MangaReader -project GD-MangaReader.xcodeproj \
  -destination 'platform=macOS,variant=Designed for iPad' CODE_SIGNING_ALLOWED=NO
```

## 配布

TestFlight または App Store 経由で配布する。iOS アプリが Apple Silicon の Mac で利用可能になるかどうかは App Store Connect 側（提供状況）で制御する。

## 既知の注意点（実機未検証）

- `AuthViewModel.swift:181` の `connectedScenes.first` は、Mac で複数ウィンドウ（シーン）を開いた場合に意図しないシーンを掴む可能性がある。
- `LibraryView.swift:83` と `NotificationService.swift:102` の `applicationState` 判定は、Mac ではウィンドウの前面/背面の扱いが iOS と異なるため、軽微にずれる可能性がある。
- Mac 実機での動作確認は未実施。

## 将来案: (A) Mac Catalyst の落とし穴

より Mac らしい UI（メニュー、ウィンドウ制御など）が必要になった場合は Catalyst を検討する。ただし以下に注意。

- バンドル ID が `maccatalyst.<元のバンドルID>` になり、Google Cloud 側の OAuth クライアント設定（バンドル ID / URL スキーム）を別途用意する必要がある。
- Keychain の entitlement（Keychain Sharing など）を Catalyst 用に設定しないと、ログイン情報の保存に失敗しうる。
- GoogleSignIn が `branch: main` に追従しているため、Catalyst 対応状況がビルド時点で変わりうる（バージョン固定が望ましい）。
