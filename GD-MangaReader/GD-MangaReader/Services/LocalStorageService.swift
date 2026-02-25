// LocalStorageService.swift
// GD-MangaReader
//
// ローカルファイルの保存・削除・パス管理サービス

import Foundation

/// ローカルストレージを管理するサービス
final class LocalStorageService: @unchecked Sendable {
    // MARK: - Singleton
    
    static let shared = LocalStorageService()
    
    // MARK: - Properties
    
    /// Documentsディレクトリ
    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// 漫画保存ディレクトリ
    var comicsDirectory: URL {
        documentsDirectory.appendingPathComponent(Config.Storage.comicsDirectoryName)
    }
    
    /// 一時ディレクトリ
    var tempDirectory: URL {
        documentsDirectory.appendingPathComponent(Config.Storage.tempDirectoryName)
    }
    
    /// 漫画メタデータ保存ファイル
    private var metadataFileURL: URL {
        documentsDirectory.appendingPathComponent("comics_metadata.json")
    }
    
    /// ファイルマネージャー
    private let fileManager = FileManager.default
    
    /// スレッドセーフなアクセスのための再帰的ロック
    private let lock = NSRecursiveLock()
    
    // MARK: - Initialization
    
    private init() {
        createDirectoriesIfNeeded()
    }
    
    private func createDirectoriesIfNeeded() {
        let directories = [comicsDirectory, tempDirectory]
        for dir in directories {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Comic Management
    
    func loadComics() throws -> [LocalComic] {
        lock.lock()
        defer { lock.unlock() }
        
        guard fileManager.fileExists(atPath: metadataFileURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: metadataFileURL)
        return try JSONDecoder().decode([LocalComic].self, from: data)
    }
    
    func saveComics(_ comics: [LocalComic]) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(comics)
        try data.write(to: metadataFileURL)
    }
    
    func addComic(_ comic: LocalComic) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var comics = (try? loadComics()) ?? []
        
        if let index = comics.firstIndex(where: { $0.driveFileId == comic.driveFileId }) {
            comics[index] = comic
        } else {
            comics.append(comic)
        }
        
        try saveComics(comics)
    }
    
    func updateComic(_ comic: LocalComic) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var comics = try loadComics()
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index] = comic
            try saveComics(comics)
        }
    }
    
    func deleteComic(_ comic: LocalComic) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let comicPath = comicsDirectory.appendingPathComponent(comic.localPath)
        if fileManager.fileExists(atPath: comicPath.path) {
            try fileManager.removeItem(at: comicPath)
        }
        
        var comics = try loadComics()
        comics.removeAll { $0.id == comic.id }
        try saveComics(comics)
    }
    
    func findComic(byDriveFileId driveFileId: String) throws -> LocalComic? {
        lock.lock()
        defer { lock.unlock() }
        
        let comics = try loadComics()
        return comics.first { $0.driveFileId == driveFileId }
    }
    
    // MARK: - File Operations
    
    func createComicDirectory(name: String) throws -> URL {
        let sanitizedName = sanitizeFileName(name)
        let comicDir = comicsDirectory.appendingPathComponent(sanitizedName)
        
        if !fileManager.fileExists(atPath: comicDir.path) {
            try fileManager.createDirectory(at: comicDir, withIntermediateDirectories: true)
        }
        
        return comicDir
    }
    
    func createTempFilePath(extension ext: String) -> URL {
        let fileName = UUID().uuidString + "." + ext
        return tempDirectory.appendingPathComponent(fileName)
    }
    
    func deleteTempFile(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
    
    func clearTempDirectory() {
        try? fileManager.removeItem(at: tempDirectory)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    func getImageFiles(in directory: URL) -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        
        return contents
            .filter { fileName in
                let ext = (fileName as NSString).pathExtension.lowercased()
                return Config.SupportedFormats.imageExtensions.contains(ext)
            }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }
    
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
    
    func calculateSize(of comic: LocalComic) -> Int64 {
        let comicPath = comicsDirectory.appendingPathComponent(comic.localPath)
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: comicPath, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        return totalSize
    }
    
    func clearAllComics() throws {
        lock.lock()
        defer { lock.unlock() }
        
        let comics = try loadComics()
        for comic in comics {
            let comicPath = comicsDirectory.appendingPathComponent(comic.localPath)
            if fileManager.fileExists(atPath: comicPath.path) {
                try fileManager.removeItem(at: comicPath)
            }
        }
        
        try saveComics([])
    }
    
    // MARK: - Helpers
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        
        if let dotIndex = sanitized.lastIndex(of: ".") {
            sanitized = String(sanitized[..<dotIndex])
        }
        
        return sanitized
    }
}
