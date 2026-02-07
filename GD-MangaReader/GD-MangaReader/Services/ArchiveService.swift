// ArchiveService.swift
// GD-MangaReader
//
// ZIP/RAR解凍ロジックを担当するサービス

import Foundation
import ZIPFoundation

/// アーカイブファイルの解凍を担当するサービス
actor ArchiveService {
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
    /// - Parameters:
    ///   - sourceURL: 解凍元ファイルのURL
    ///   - destinationURL: 解凍先ディレクトリのURL
    ///   - progress: 進捗コールバック (0.0〜1.0)
    /// - Returns: 解凍された画像ファイル名の配列（ソート済み）
    func extract(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: ((Double) -> Void)? = nil
    ) async throws -> [String] {
        guard let archiveType = ArchiveType(fileName: sourceURL.lastPathComponent) else {
            throw ArchiveServiceError.unsupportedFormat
        }
        
        // ディレクトリ作成
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
        
        switch archiveType {
        case .zip:
            try await extractZIP(from: sourceURL, to: destinationURL, progress: progress)
        case .rar:
            // RAR対応は後から追加（UnrarKitの手動組み込みが必要）
            throw ArchiveServiceError.rarNotSupported
        }
        
        // 画像ファイルを取得してソート
        let imageFiles = LocalStorageService.shared.getImageFiles(in: destinationURL)
        
        return imageFiles
    }
    
    // MARK: - ZIP Extraction
    
    private func extractZIP(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: ((Double) -> Void)?
    ) async throws {
        let fileManager = FileManager.default
        
        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            throw ArchiveServiceError.cannotOpenArchive
        }
        
        // エントリー数を取得してプログレス計算用
        let entries = Array(archive)
        let totalEntries = entries.count
        var processedEntries = 0
        
        for entry in entries {
            // ディレクトリエントリはスキップ
            guard entry.type == .file else {
                processedEntries += 1
                continue
            }
            
            // 隠しファイル（.で始まる）やMacのメタデータはスキップ
            let fileName = entry.path
            if fileName.hasPrefix(".") || fileName.hasPrefix("__MACOSX") {
                processedEntries += 1
                continue
            }
            
            // 画像ファイルのみを抽出
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard Config.SupportedFormats.imageExtensions.contains(ext) else {
                processedEntries += 1
                continue
            }
            
            // ファイル名のみ取得（フォルダ構造をフラット化）
            let baseName = (fileName as NSString).lastPathComponent
            let destinationPath = destinationURL.appendingPathComponent(baseName)
            
            // 既存ファイルがあれば削除
            if fileManager.fileExists(atPath: destinationPath.path) {
                try? fileManager.removeItem(at: destinationPath)
            }
            
            // 解凍
            _ = try archive.extract(entry, to: destinationPath)
            
            // 進捗更新
            processedEntries += 1
            if let progress = progress {
                let progressValue = Double(processedEntries) / Double(totalEntries)
                await MainActor.run {
                    progress(progressValue)
                }
            }
        }
    }
    
    // MARK: - RAR Extraction (Placeholder)
    
    /// RAR解凍（UnrarKit統合後に実装）
    /// 現在はエラーを投げるのみ
    private func extractRAR(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: ((Double) -> Void)?
    ) async throws {
        // TODO: UnrarKitを手動で組み込んだ後に実装
        // 以下のようなコードになる予定：
        //
        // guard let archive = URKArchive(path: sourceURL.path) else {
        //     throw ArchiveServiceError.cannotOpenArchive
        // }
        // try archive.extractFiles(to: destinationURL.path, overwrite: true, progress: { progress, _ in
        //     progressCallback?(Double(progress) / 100.0)
        // })
        
        throw ArchiveServiceError.rarNotSupported
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
