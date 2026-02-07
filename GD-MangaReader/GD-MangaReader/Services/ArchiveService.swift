// ArchiveService.swift
// GD-MangaReader
//
// ZIP/RAR解凍ロジックを担当するサービス

import Foundation
import ZIPFoundation

/// アーカイブファイルの解凍を担当するサービス
final class ArchiveService {
    // MARK: - Singleton
    
    static let shared = ArchiveService()
    
    private init() {}
    
    // MARK: - Types
    
    enum ArchiveType {
        case zip
        case rar
        
        init?(fileName: String) {
            let ext = (fileName as NSString).pathExtension.lowercased()
            switch ext {
            case "zip", "cbz":
                self = .zip
            case "rar", "cbr":
                self = .rar
            default:
                return nil
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// アーカイブファイルを解凍し、画像ファイル一覧を返す
    func extract(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [String] {
        guard let archiveType = ArchiveType(fileName: sourceURL.lastPathComponent) else {
            throw ArchiveServiceError.unsupportedFormat
        }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
        
        switch archiveType {
        case .zip:
            try await extractZIP(from: sourceURL, to: destinationURL, progress: progress)
        case .rar:
            throw ArchiveServiceError.rarNotSupported
        }
        
        let imageFiles = LocalStorageService.shared.getImageFiles(in: destinationURL)
        return imageFiles
    }
    
    // MARK: - ZIP Extraction
    
    private func extractZIP(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await Task.detached {
            let fileManager = FileManager.default
            
            guard let archive = Archive(url: sourceURL, accessMode: .read) else {
                throw ArchiveServiceError.cannotOpenArchive
            }
            
            let entries = Array(archive)
            let totalEntries = entries.count
            var processedEntries = 0
            
            for entry in entries {
                guard entry.type == .file else {
                    processedEntries += 1
                    continue
                }
                
                let fileName = entry.path
                if fileName.hasPrefix(".") || fileName.hasPrefix("__MACOSX") {
                    processedEntries += 1
                    continue
                }
                
                let ext = (fileName as NSString).pathExtension.lowercased()
                guard Config.SupportedFormats.imageExtensions.contains(ext) else {
                    processedEntries += 1
                    continue
                }
                
                let baseName = (fileName as NSString).lastPathComponent
                let destinationPath = destinationURL.appendingPathComponent(baseName)
                
                if fileManager.fileExists(atPath: destinationPath.path) {
                    try? fileManager.removeItem(at: destinationPath)
                }
                
                _ = try archive.extract(entry, to: destinationPath)
                
                processedEntries += 1
                if let progress = progress {
                    let progressValue = Double(processedEntries) / Double(totalEntries)
                    progress(progressValue)
                }
            }
        }.value
    }
}

// MARK: - Errors

enum ArchiveServiceError: LocalizedError {
    case unsupportedFormat
    case cannotOpenArchive
    case extractionFailed(String)
    case rarNotSupported
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "サポートされていないファイル形式です"
        case .cannotOpenArchive:
            return "アーカイブファイルを開けません"
        case .extractionFailed(let message):
            return "解凍に失敗しました: \(message)"
        case .rarNotSupported:
            return "RAR形式は現在サポートされていません。ZIPまたはCBZ形式をお使いください。"
        }
    }
}
