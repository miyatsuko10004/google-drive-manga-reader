# Firebase App Distribution での配信

実機を有線接続せずに、最新ビルドをテスターの端末へインストールするための仕組みです（Issue #46）。

## 仕組み

1. GitHub Actions の `Distribute (Firebase App Distribution)` ワークフロー（`.github/workflows/distribute.yml`）を **手動実行（workflow_dispatch）** する。
2. macos-15 ランナーで `Secrets.xcconfig` を Secrets から生成し、`xcodegen generate` でプロジェクトを作成する。
3. 一時 keychain に配布用証明書（.p12）をインポートし、Ad Hoc プロビジョニングプロファイルを配置する。
4. `xcodebuild archive`（`CURRENT_PROJECT_VERSION` は `github.run_number`）→ `xcodebuild -exportArchive`（method: `ad-hoc`）で IPA を作成する。
5. 公式 `firebase-tools` CLI とサービスアカウントで `firebase appdistribution:distribute` を実行し、テスターグループへ配信する。
6. テスターは Firebase App Distribution のメール通知（または Tester アプリ / Web クリップ）から端末へインストールする。

セキュリティ上、このワークフローは `pull_request` / `push` / `pull_request_target` では動かしません。署名用の秘密情報を外部 PR から読めないようにするためです。必要な Secrets が 1 つでも欠けている場合、先頭ステップで fail します。

`DEVELOPMENT_TEAM` とバンドル ID は `project.yml` を変更せず、`xcodebuild` の引数で渡します。

## 事前準備チェックリスト（人間の作業が必要）

- [ ] バンドル ID の確定（現在は `com.example.GD-MangaReader`。`com.example` はそのまま配布できないため、自分のドメイン等で確定する。確定後は `BUNDLE_ID` Secret で上書きするか、`project.yml` を別 PR で更新する）
- [ ] Apple Developer Program への加入（Ad Hoc 配布に必須。有料）
- [ ] 配布用証明書（Apple Distribution）の作成と .p12 書き出し
- [ ] App ID の登録（確定したバンドル ID）と Ad Hoc プロビジョニングプロファイルの作成
- [ ] テスト端末の UDID 登録（Apple Developer サイトの Devices。登録後にプロファイルを再作成する）
- [ ] Firebase プロジェクトの作成
- [ ] Firebase に iOS アプリを登録（バンドル ID を一致させる）し、App ID（`1:xxxx:ios:xxxx`）を控える
- [ ] App Distribution を有効化し、テスターグループ（既定 alias: `testers`）とテスターを登録
- [ ] サービスアカウントの作成（ロール: Firebase App Distribution 管理者）と JSON キー発行
- [ ] GitHub Secrets の登録（下記）
- [ ] 初回実行と、端末へのインストール確認

## Secrets 一覧

リポジトリの Settings > Secrets and variables > Actions に登録します。

| Secret | 内容 | 作り方 |
| --- | --- | --- |
| `APPLE_CERT_P12_BASE64` | 配布用証明書 .p12 の base64 | `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERT_PASSWORD` | .p12 書き出し時のパスワード | キーチェーンアクセスで書き出し時に設定 |
| `PROVISIONING_PROFILE_BASE64` | Ad Hoc プロファイルの base64 | `base64 -i profile.mobileprovision \| pbcopy` |
| `APPLE_TEAM_ID` | Apple Developer の Team ID（10 桁） | Developer サイトの Membership |
| `FIREBASE_APP_ID` | Firebase の iOS アプリ ID | Firebase コンソール > プロジェクトの設定 > アプリ |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | サービスアカウント JSON キーの中身（そのまま貼り付け） | Google Cloud コンソールでキー発行 |
| `GID_CLIENT_ID` | Google OAuth クライアント ID（`.apps.googleusercontent.com` を除いた部分） | Google Cloud コンソール |
| `GID_REVERSED_CLIENT_ID` | 上記を逆順にした URL スキーム（`com.googleusercontent.apps.<id>`） | 同上 |
| `BUNDLE_ID`（任意） | バンドル ID。未設定なら `com.example.GD-MangaReader` | 確定したバンドル ID |

注意:

- 配布版でも Google ログインを使うため、`GID_*` はダミー値ではなく実値が必要です。OAuth クライアントはバンドル ID に紐づくので、バンドル ID を変えた場合は作り直します。
- Secrets の内容や .p12 / .mobileprovision / サービスアカウント JSON をコミットしないでください。

## 実行手順

1. 上記チェックリストと Secrets 登録を完了する。
2. GitHub の Actions タブで `Distribute (Firebase App Distribution)` を選び、`Run workflow` を押す。
3. 必要ならブランチ、リリースノート、配信先グループ（カンマ区切り alias）を指定する。
4. 完了後、テスターにメールが届く。端末で通知から Firebase にサインインしてインストールする。

失敗したときは、先頭ステップのメッセージ（未設定の Secret 名）を確認してください。署名エラーの多くは、プロファイルに端末 UDID またはバンドル ID が含まれていないことが原因です。

## ExportOptions のテンプレート

`docs/ExportOptions.plist.example` に秘密情報なしのテンプレートがあります。ワークフローは同じ形式のファイルを実行時に生成します。手元で試す場合は `YOUR_*` を置き換えて使ってください。
