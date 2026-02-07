// LocalComic.swift
// GD-MangaReader
//
// ダウンロード済み漫画の管理モデル

import Foundation

/// ダウンロード済みの漫画を表すモデル
struct LocalComic: Identifiable, Codable, Hashable {
    /// ユニークID（UUIDまたはDriveファイルID）
    let id: String
    
    /// 漫画タイトル（ファイル名から拡張子を除いたもの）
    let title: String
    
    /// 元のDriveファイルID
    let driveFileId: String
    
    /// ローカル保存ディレクトリのパス（Documents相対）
    let localPath: String
    
    /// 画像ファイル名の配列（ソート済み）
    var imageFileNames: [String]
    
    /// 最後に読んだページ番号（0-indexed）
    var lastReadPage: Int
    
    /// ダウンロード日時
    let downloadedAt: Date
    
    /// 最終閲覧日時
    var lastReadAt: Date?
    
    /// 元のファイルサイズ（バイト）
    let originalFileSize: Int64?
    
    /// ダウンロードステータス
    var status: DownloadStatus
    
    // MARK: - Computed Properties
    
    /// 総ページ数
    var pageCount: Int {
        imageFileNames.count
    }
    
    /// 読了率（0.0〜1.0）
    var readingProgress: Double {
        guard pageCount > 0 else { return 0 }
        return Double(lastReadPage + 1) / Double(pageCount)
    }
    
    /// ローカルディレクトリの絶対パス
    var absolutePath: URL {
        LocalStorageService.shared.comicsDirectory.appendingPathComponent(localPath)
    }
    
    /// 画像ファイルの絶対パス配列
    var imagePaths: [URL] {
        imageFileNames.map { absolutePath.appendingPathComponent($0) }
    }
    
    // MARK: - Initialization
    
    init(
        id: String = UUID().uuidString,
        title: String,
        driveFileId: String,
        localPath: String,
        imageFileNames: [String] = [],
        lastReadPage: Int = 0,
        downloadedAt: Date = Date(),
        lastReadAt: Date? = nil,
        originalFileSize: Int64? = nil,
        status: DownloadStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.driveFileId = driveFileId
        self.localPath = localPath
        self.imageFileNames = imageFileNames
        self.lastReadPage = lastReadPage
        self.downloadedAt = downloadedAt
        self.lastReadAt = lastReadAt
        self.originalFileSize = originalFileSize
        self.status = status
    }
}

// MARK: - Download Status

/// ダウンロードステータス
enum DownloadStatus: String, Codable {
    /// ダウンロード待機中
    case pending
    /// ダウンロード中
    case downloading
    /// 解凍中
    case extracting
    /// 完了
    case completed
    /// エラー
    case failed
    
    var displayName: String {
        switch self {
        case .pending: return "待機中"
        case .downloading: return "ダウンロード中"
        case .extracting: return "解凍中"
        case .completed: return "完了"
        case .failed: return "エラー"
        }
    }
}

// MARK: - Mock Data

extension LocalComic {
    static let mock = LocalComic(
        title: "サンプル漫画",
        driveFileId: "mock-drive-id",
        localPath: "sample-manga",
        imageFileNames: ["001.jpg", "002.jpg", "003.jpg"],
        lastReadPage: 0,
        status: .completed
    )
}
