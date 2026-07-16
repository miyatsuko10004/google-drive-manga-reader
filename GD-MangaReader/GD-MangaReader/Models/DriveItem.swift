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
    
    /// 画像の幅（オプション）
    let width: Int?
    
    /// 画像の高さ（オプション）
    let height: Int?
    
    /// 表示用に分解した名前（アーカイブは拡張子を除いてから解析する）
    /// 以前はComputed Propertyだったが、スクロール時の再レンダリングのたびに
    /// 重い正規表現処理が走るのを防ぐため、初期化時に1度だけ計算するStored Propertyに変更
    let displayName: MangaDisplayName

    // MARK: - Initialization

    init(
        id: String,
        name: String,
        mimeType: String,
        size: Int64?,
        thumbnailURL: URL?,
        parentId: String?,
        createdTime: Date?,
        modifiedTime: Date?,
        width: Int?,
        height: Int?
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.thumbnailURL = thumbnailURL
        self.parentId = parentId
        self.createdTime = createdTime
        self.modifiedTime = modifiedTime
        self.width = width
        self.height = height

        // isArchiveと同等の判定ロジック（selfを参照できないためローカルで判定）
        let ext = (name as NSString).pathExtension.lowercased()
        let isArchiveType = Config.SupportedFormats.archiveExtensions.contains(ext) ||
            mimeType == "application/zip" ||
            mimeType == "application/x-zip-compressed" ||
            mimeType == "application/x-rar-compressed" ||
            mimeType == "application/vnd.rar" ||
            mimeType == "application/x-cbz" ||
            mimeType == "application/x-cbr"

        let base = isArchiveType ? (name as NSString).deletingPathExtension : name
        self.displayName = MangaDisplayName(parsing: base)
    }

    // MARK: - Computed Properties
    
    /// フォルダかどうか
    var isFolder: Bool {
        mimeType == "application/vnd.google-apps.folder"
    }
    
    /// アーカイブファイルかどうか (ZIP/RAR/CBZ/CBR)
    var isArchive: Bool {
        Config.SupportedFormats.archiveExtensions.contains(fileExtension.lowercased()) ||
        mimeType == "application/zip" ||
        mimeType == "application/x-zip-compressed" ||
        mimeType == "application/x-rar-compressed" ||
        mimeType == "application/vnd.rar" ||
        mimeType == "application/x-cbz" ||
        mimeType == "application/x-cbr"
    }
    
    /// 画像ファイルかどうか
    var isImage: Bool {
        Config.SupportedFormats.imageExtensions.contains(fileExtension.lowercased()) ||
        mimeType.hasPrefix("image/")
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

// MARK: - Display Name Parsing

/// 「作品名[作者名]」（シリーズフォルダ）や「[作者名]作品名 第〇〇巻」（アーカイブ）形式の
/// 名前を作品名・作者名・巻数に分解した表示用モデル
struct MangaDisplayName: Hashable, Sendable {
    /// 作品名（分解できない名前はそのまま全体が入る）
    let title: String

    /// 作者名（`[...]` が含まれない名前ではnil）
    let author: String?

    /// 巻数表記（例: "第01巻"）。含まれない名前ではnil
    let volume: String?

    /// 作品名の下に添える補足行（例: "第01巻 · 尾田栄一郎"）
    var subtitle: String? {
        let parts = [volume, author].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(parsing rawName: String) {
        var working = rawName.trimmingCharacters(in: .whitespaces)
        var author: String?

        // 末尾の「[作者名]」（フォルダ形式）または先頭の「[作者名]」（アーカイブ形式）を抽出する。
        // 末尾を先に判定するのは、「[HQ]鬼滅の刃[吾峠呼世晴]」のように両端にブラケットがある名前で
        // 末尾の作者名タグを優先するため。アーカイブ名は（拡張子除去後）「第〇〇巻」で終わり
        // 「]」で終わることはないので、この順序でアーカイブ形式の判定を妨げることはない。
        // 作者名か残りの作品名が空になる場合は分解せず、名前全体を作品名として扱う
        if working.hasSuffix("]"), let open = working.lastIndex(of: "[") {
            let candidate = working[working.index(after: open)..<working.index(before: working.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            let rest = working[..<open].trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty && !rest.isEmpty {
                author = candidate
                working = rest
            }
        } else if working.hasPrefix("["), let close = working.firstIndex(of: "]") {
            let candidate = working[working.index(after: working.startIndex)..<close]
                .trimmingCharacters(in: .whitespaces)
            let rest = working[working.index(after: close)...]
                .trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty && !rest.isEmpty {
                author = candidate
                working = rest
            }
        }

        // 末尾の「第〇〇巻」を巻数として切り出す
        var volume: String?
        if let range = working.range(of: "第[0-9０-９]+巻$", options: .regularExpression) {
            let rest = working[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                volume = String(working[range])
                working = rest
            }
        }

        self.title = working
        self.author = author
        self.volume = volume
    }
}

// MARK: - LocalComic Extension

extension DriveItem {
    /// LocalComicからDriveItemオブジェクトを生成するマッピングイニシャライザ
    /// - Parameter localComic: ダウンロード済みの漫画データ
    init(from localComic: LocalComic) {
        self.init(
            id: localComic.driveFileId,
            name: localComic.title,
            mimeType: "application/zip", // 一括アーカイブを模倣
            size: localComic.originalFileSize,
            thumbnailURL: localComic.imagePaths.first, // ローカルの絶対URLをサムネイルとして使用
            parentId: nil,
            createdTime: localComic.downloadedAt,
            modifiedTime: localComic.lastReadAt,
            width: nil,
            height: nil
        )
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
        modifiedTime: Date(),
        width: nil,
        height: nil
    )
    
    static let mockZipFile = DriveItem(
        id: "file-1",
        name: "ワンピース第1巻.zip",
        mimeType: "application/zip",
        size: 85_000_000,
        thumbnailURL: nil,
        parentId: "folder-1",
        createdTime: Date(),
        modifiedTime: Date(),
        width: nil,
        height: nil
    )
    
    static let mockRarFile = DriveItem(
        id: "file-2",
        name: "進撃の巨人.rar",
        mimeType: "application/x-rar-compressed",
        size: 120_000_000,
        thumbnailURL: nil,
        parentId: "folder-1",
        createdTime: Date(),
        modifiedTime: Date(),
        width: nil,
        height: nil
    )
    
    static let mockItems: [DriveItem] = [
        mockFolder,
        mockZipFile,
        mockRarFile
    ]
}
