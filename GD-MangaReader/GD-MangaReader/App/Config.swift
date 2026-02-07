// Config.swift
// GD-MangaReader
//
// アプリケーション設定定数

import Foundation

/// アプリケーション設定
enum Config {
    /// Google Drive APIのスコープ
    enum GoogleAPI {
        /// Google Drive読み取り専用スコープ
        static let driveReadOnlyScope = "https://www.googleapis.com/auth/drive.readonly"
        
        /// 必要なスコープ一覧
        static let scopes: [String] = [
            driveReadOnlyScope
        ]
    }
    
    /// ローカルストレージ設定
    enum Storage {
        /// ダウンロードした漫画を保存するディレクトリ名
        static let comicsDirectoryName = "Comics"
        
        /// 一時ファイル用ディレクトリ名
        static let tempDirectoryName = "Temp"
    }
    
    /// サポートするファイル形式
    enum SupportedFormats {
        /// 対象MIMEタイプ
        static let mimeTypes: [String] = [
            "application/vnd.google-apps.folder",
            "application/zip",
            "application/x-zip-compressed",
            "application/x-rar-compressed",
            "application/vnd.rar",
            "application/x-cbz",
            "application/x-cbr"
        ]
        
        /// 画像ファイル拡張子
        static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        
        /// アーカイブファイル拡張子
        static let archiveExtensions: Set<String> = ["zip", "cbz", "rar", "cbr"]
    }
}
