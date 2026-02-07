// DriveItem.swift
// GD-MangaReader
//
// Google Driveファイル/フォルダのメタデータモデル

import Foundation

/// Google Drive上のファイル/フォルダを表すモデル
struct DriveItem: Identifiable, Hashable, Sendable {
    /// Google Drive固有のファイルID
    let id: String
    
    /// ファイル名
    let name: String
    
    /// MIMEタイプ
    let mimeType: String
    
    /// ファイルサイズ（バイト）- フォルダの場合はnil
    let size: Int64?
    
    /// サムネイルURL
    let thumbnailURL: URL?
    
    /// 親フォルダID
    let parentId: String?
    
    /// 作成日時
    let createdTime: Date?
    
    /// 更新日時
    let modifiedTime: Date?
    
    // MARK: - Computed Properties
    
    /// フォルダかどうか
    var isFolder: Bool {
        mimeType == "application/vnd.google-apps.folder"
    }
    
    /// アーカイブファイルかどうか (ZIP/RAR/CBZ/CBR)
    var isArchive: Bool {
        Config.SupportedFormats.archiveExtensions.contains(fileExtension.lowercased())
    }
    
    /// 画像ファイルかどうか
    var isImage: Bool {
        Config.SupportedFormats.imageExtensions.contains(fileExtension.lowercased())
    }
    
    /// ファイル拡張子
    var fileExtension: String {
        (name as NSString).pathExtension
    }
    
    /// 人間が読みやすいファイルサイズ表記
    var formattedSize: String {
        guard let size = size else { return "-" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    /// 表示用アイコン名（SF Symbols）
    var iconName: String {
        if isFolder {
            return "folder.fill"
        }
        switch fileExtension.lowercased() {
        case "zip", "cbz":
            return "doc.zipper"
        case "rar", "cbr":
            return "doc.zipper"
        case "jpg", "jpeg", "png", "webp", "gif":
            return "photo"
        default:
            return "doc"
        }
    }
    
    /// アイコンの色
    var iconColor: String {
        if isFolder {
            return "folder"
        }
        if isArchive {
            return "archive"
        }
        return "default"
    }
}

// MARK: - Mock Data for Preview

extension DriveItem {
    static let mockFolder = DriveItem(
        id: "folder-1",
        name: "漫画フォルダ",
        mimeType: "application/vnd.google-apps.folder",
        size: nil,
        thumbnailURL: nil,
        parentId: nil,
        createdTime: Date(),
        modifiedTime: Date()
    )
    
    static let mockZipFile = DriveItem(
        id: "file-1",
        name: "ワンピース第1巻.zip",
        mimeType: "application/zip",
        size: 85_000_000,
        thumbnailURL: nil,
        parentId: "folder-1",
        createdTime: Date(),
        modifiedTime: Date()
    )
    
    static let mockRarFile = DriveItem(
        id: "file-2",
        name: "進撃の巨人.rar",
        mimeType: "application/x-rar-compressed",
        size: 120_000_000,
        thumbnailURL: nil,
        parentId: "folder-1",
        createdTime: Date(),
        modifiedTime: Date()
    )
    
    static let mockItems: [DriveItem] = [
        mockFolder,
        mockZipFile,
        mockRarFile
    ]
}
