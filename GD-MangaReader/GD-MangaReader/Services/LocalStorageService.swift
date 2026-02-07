// LocalStorageService.swift
// GD-MangaReader
//
// ローカルファイルの保存・削除・パス管理サービス

import Foundation

/// ローカルストレージを管理するサービス
actor LocalStorageService {
    // MARK: - Singleton
    
    static let shared = LocalStorageService()
    
    // MARK: - Properties
    
    /// Documentsディレクトリ
    nonisolated var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// 漫画保存ディレクトリ
    nonisolated var comicsDirectory: URL {
        documentsDirectory.appendingPathComponent(Config.Storage.comicsDirectoryName)
    }
    
    /// 一時ディレクトリ
    nonisolated var tempDirectory: URL {
        documentsDirectory.appendingPathComponent(Config.Storage.tempDirectoryName)
    }
    
    /// 漫画メタデータ保存ファイル
    private nonisolated var metadataFileURL: URL {
        documentsDirectory.appendingPathComponent("comics_metadata.json")
    }
    
    /// ファイルマネージャー
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    private init() {
        // ディレクトリ作成はsync処理として初期化時に行う
        createDirectoriesIfNeeded()
    }
    
    /// 必要なディレクトリを作成
    private nonisolated func createDirectoriesIfNeeded() {
        let directories = [comicsDirectory, tempDirectory]
        for dir in directories {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Comic Management
    
    /// 保存済み漫画のメタデータを読み込み
    func loadComics() throws -> [LocalComic] {
        guard fileManager.fileExists(atPath: metadataFileURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: metadataFileURL)
        return try JSONDecoder().decode([LocalComic].self, from: data)
    }
    
    /// 漫画メタデータを保存
    func saveComics(_ comics: [LocalComic]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(comics)
        try data.write(to: metadataFileURL)
    }
    
    /// 漫画を追加
    func addComic(_ comic: LocalComic) throws {
        var comics = (try? loadComics()) ?? []
        
        // 既存のものがあれば更新
        if let index = comics.firstIndex(where: { $0.driveFileId == comic.driveFileId }) {
            comics[index] = comic
        } else {
            comics.append(comic)
        }
        
        try saveComics(comics)
    }
    
    /// 漫画を更新
    func updateComic(_ comic: LocalComic) throws {
        var comics = try loadComics()
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index] = comic
            try saveComics(comics)
        }
    }
    
    /// 漫画を削除（ファイルも含む）
    func deleteComic(_ comic: LocalComic) throws {
        // ファイル削除
        let comicPath = comicsDirectory.appendingPathComponent(comic.localPath)
        if fileManager.fileExists(atPath: comicPath.path) {
            try fileManager.removeItem(at: comicPath)
        }
        
        // メタデータから削除
        var comics = try loadComics()
        comics.removeAll { $0.id == comic.id }
        try saveComics(comics)
    }
    
    /// DriveファイルIDで漫画を検索
    func findComic(byDriveFileId driveFileId: String) throws -> LocalComic? {
        let comics = try loadComics()
        return comics.first { $0.driveFileId == driveFileId }
    }
    
    // MARK: - File Operations
    
    /// 漫画用のディレクトリを作成
    func createComicDirectory(name: String) throws -> URL {
        let sanitizedName = sanitizeFileName(name)
        let comicDir = comicsDirectory.appendingPathComponent(sanitizedName)
        
        if !fileManager.fileExists(atPath: comicDir.path) {
            try fileManager.createDirectory(at: comicDir, withIntermediateDirectories: true)
        }
        
        return comicDir
    }
    
    /// 一時ファイルのパスを生成
    func createTempFilePath(extension ext: String) -> URL {
        let fileName = UUID().uuidString + "." + ext
        return tempDirectory.appendingPathComponent(fileName)
    }
    
    /// 一時ファイルを削除
    func deleteTempFile(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
    
    /// 一時ディレクトリをクリア
    func clearTempDirectory() {
        try? fileManager.removeItem(at: tempDirectory)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    /// フォルダ内の画像ファイルを取得（ソート済み）
    nonisolated func getImageFiles(in directory: URL) -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        
        return contents
            .filter { fileName in
                let ext = (fileName as NSString).pathExtension.lowercased()
                return Config.SupportedFormats.imageExtensions.contains(ext)
            }
            .sorted { lhs, rhs in
                // 自然順ソート（001, 002, ... 010, 011）
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }
    
    /// 使用ストレージサイズを計算
    func calculateStorageUsage() -> Int64 {
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: comicsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        return totalSize
    }
    
    // MARK: - Helpers
    
    /// ファイル名をサニタイズ
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        
        // 拡張子を除去
        if let dotIndex = sanitized.lastIndex(of: ".") {
            sanitized = String(sanitized[..<dotIndex])
        }
        
        return sanitized
    }
}
