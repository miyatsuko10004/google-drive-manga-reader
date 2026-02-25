# GD-MangaReader

Google Drive上のZIP/RAR/CBZ/CBR形式コミックや画像フォルダを、iOSデバイス（iPhone / iPad）にダウンロードして快適に読むためのマンガビューアーアプリです。

## 特徴 (Features)

*   **Google Drive 連携**
    *   OAuthを用いたGoogle Sign-In対応。
    *   マイドライブ内のフォルダやファイルをアプリ内でブラウジング（Grid / List表示切替可能）。
*   **多様なファイルフォーマット対応**
    *   アーカイブ形式: `.zip` `.rar` `.cbz` `.cbr` 
    *   画像形式（フォルダ内ストリーミング閲覧）: `.jpg` `.jpeg` `.png` `.heic`
*   **オフライン閲覧・ダウンロード機能**
    *   ZIP/RAR/CBZ等のアーカイブファイルをローカルのドキュメントフォルダへ一括ダウンロード・展開。
    *   シリーズ（フォルダ）単位での一括ダウンロード対応。
    *   バックグラウンドでの進行状況（プログレスバー）表示。
*   **高機能ビューアー (Manga Reader)**
    *   横読み（日本式・右から左 / アメコミ式・左から右）および、縦読み（縦スクロール）に対応。
    *   iPadやiPhone横向き時の「見開き表示」に対応。
    *   ピンチイン・ピンチアウトでの画像ズーム機能。
    *   読書中のページプログレス自動保存。

## 環境要件 (Requirements)

*   **OS:** macOS 14+ (開発環境) / iOS 17.0+ (実行環境)
*   **IDE:** Xcode 15 / 16+
*   **Tool:** XcodeGen

## 使用しているライブラリ (Dependencies)

*   [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS)
*   [GoogleAPIClientForREST](https://github.com/google/google-api-objectivec-client-for-rest)
*   [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (ZIP/CBZの解凍処理)
*   [Kingfisher](https://github.com/onevcat/Kingfisher) (画像キャッシュ・非同期読み込み)

---

## セットアップ手順 (Setup Instructions)

本プロジェクトは **XcodeGen** を使用して `*.xcodeproj` ファイルを動的に生成します。
また、Google Sign-In用の認証情報はGitHub上にコミットされていないため、手元で設定ファイルを用意する必要があります。

### 1. Google Cloud Console で Oauth クライアント ID を取得する
1. [Google Cloud Console](https://console.cloud.google.com/) にアクセスし、プロジェクトを作成します。
2. 「APIとサービス」 > 「ライブラリ」から **Google Drive API** を有効化します。
3. 「認証情報」から「OAuth クライアント ID」を作成（アプリケーションの種類: iOS）し、クリップボードに **Client ID** をコピーします。
    * 例: `000000000000-dummyid.apps.googleusercontent.com`

### 2. `Secrets.xcconfig` の作成
プロジェクト内に `GD-MangaReader/Secrets.xcconfig` ファイルを作成（または編集）し、以下のフォーマットで記述します。
*(このファイルは `.gitignore` に含まれており、コミットされません)*

```text
// GD-MangaReader/Secrets.xcconfig
// ※ .apps.googleusercontent.com のサフィックスは除外してください
GID_CLIENT_ID = 000000000000-dummyid

// ※ 上記IDを「com.googleusercontent.apps.」に繋げたもの
GID_REVERSED_CLIENT_ID = com.googleusercontent.apps.000000000000-dummyid
```

### 3. プロジェクトの生成とビルド
Homebrew などで [XcodeGen](https://github.com/yonaskolb/XcodeGen) をインストールしたのち、ターミナルで以下のコマンドを実行します。

```bash
# XcodeGen のインストール（未インストールの場合）
brew install xcodegen

# プロジェクトのルートディレクトリに移動
cd /path/to/google-drive-manga-reader

# GD-MangaReader ディレクトリに移動し XcodeGen を実行
cd GD-MangaReader
xcodegen
```

成功すると `GD-MangaReader.xcodeproj` が生成されます。
生成されたプロジェクトを開き、シミュレータまたは実機を選択して `Cmd + R` で実行してください。

---

## トラブルシューティング

*   **"Oauth client was not found" というエラーが出てログインできない場合:**
    `Secrets.xcconfig` の `GID_CLIENT_ID` や `GID_REVERSED_CLIENT_ID` が正しく設定されていません。正しい値に修正してから、もう一度 `xcodegen` を実行し、Xcode 上で **Product > Clean Build Folder** (`Cmd + Shift + K`) を行ってから再ビルドしてください。
*   **シミュレータでGoogleログイン画面が表示されたあと真っ白になる場合:**
    Xcode 16 + iOS 18 環境などで発生するWebViewのバグの可能性があります。`SFSafariViewController`の設定やシミュレータの再起動をお試しください。

---

## ライセンス (License)

This project is intended for personal use.
