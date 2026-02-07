// DownloaderViewModel.swift
// GD-MangaReader
//
// ダウンロード・解凍処理の進捗管理ViewModel

import Foundation
import SwiftUI
import GoogleAPIClientForREST_Drive

/// ダウンロード・解凍処理を管理するViewModel
@MainActor
@Observable
final class DownloaderViewModel {
    // MARK: - Properties
    
    /// ダウンロード進捗（0.0〜1.0）
    private(set) var downloadProgress: Double = 0
    
    /// 解凍進捗（0.0〜1.0）
    private(set) var extractProgress: Double = 0
    
    /// 現在のステータス
    private(set) var status: DownloadStatus = .pending
    
    /// エラーメッセージ
    private(set) var errorMessage: String?
    
    /// 処理中のファイル名
    private(set) var currentFileName: String?
    
    /// 処理中かどうか
    var isProcessing: Bool {
        status == .downloading || status == .extracting
    }
    
    /// 合計進捗（ダウンロード50% + 解凍50%）
    var totalProgress: Double {
        switch status {
        case .pending:
            return 0
        case .downloading:
            return downloadProgress * 0.5
        case .extracting:
            return 0.5 + extractProgress * 0.5
        case .completed:
            return 1.0
        case .failed:
            return 0
        }
    }
    
    // MARK: - Dependencies
    
    private let driveService: DriveService
    private let archiveService = ArchiveService.shared
    private let storageService = LocalStorageService.shared
    
    // MARK: - Initialization
    
    init(driveService: DriveService = DriveService()) {
        self.driveService = driveService
    }
    
    // MARK: - Public Methods
    
    /// DriveServiceに認証情報を設定
    func configure(with authorizer: (any GTMFetcherAuthorizationProtocol)?) async {
        guard let authorizer = authorizer else { return }
        await driveService.configure(with: authorizer)
    }
    
    /// ファイルをダウンロード・解凍してLocalComicを作成
    func downloadAndExtract(item: DriveItem) async -> LocalComic? {
        reset()
        currentFileName = item.name
        
        do {
            // 既にダウンロード済みかチェック
            if let existingComic = try await storageService.findComic(byDriveFileId: item.id) {
                if existingComic.status == .completed {
                    return existingComic
                }
            }
            
            // 1. ダウンロード
            status = .downloading
            let tempFileURL = await downloadFile(item: item)
            
            guard let tempFileURL = tempFileURL else {
                throw DownloaderError.downloadFailed
            }
            
            // 2. 解凍先ディレクトリを作成
            status = .extracting
            let comicDirectory = try await storageService.createComicDirectory(name: item.name)
            
            // 3. 解凍
            let imageFiles = try await archiveService.extract(
                from: tempFileURL,
                to: comicDirectory
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.extractProgress = progress
                }
            }
            
            // 4. 一時ファイル削除
            await storageService.deleteTempFile(at: tempFileURL)
            
            // 5. LocalComic作成・保存
            let localPath = comicDirectory.lastPathComponent
            let comic = LocalComic(
                title: item.name.replacingOccurrences(of: ".\(item.fileExtension)", with: ""),
                driveFileId: item.id,
                localPath: localPath,
                imageFileNames: imageFiles,
                originalFileSize: item.size,
                status: .completed
            )
            
            try await storageService.addComic(comic)
            
            status = .completed
            return comic
            
        } catch {
            status = .failed
            errorMessage = error.localizedDescription
            return nil
        }
    }
    
    /// リセット
    func reset() {
        downloadProgress = 0
        extractProgress = 0
        status = .pending
        errorMessage = nil
        currentFileName = nil
    }
    
    // MARK: - Private Methods
    
    /// ファイルをダウンロード
    private func downloadFile(item: DriveItem) async -> URL? {
        do {
            let request = try await driveService.getDownloadRequest(for: item.id)
            let expectedSize = item.size ?? 0
            
            // ダウンロードデリゲートを作成
            let delegate = DownloadDelegate(
                expectedContentLength: expectedSize
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            
            // カスタムセッションでダウンロード
            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
            
            defer { session.invalidateAndCancel() }
            
            let (tempLocalURL, response) = try await session.download(for: request)
            
            // HTTPエラーチェック
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw DownloaderError.httpError
            }
            
            // 一時ファイルを保存先に移動
            let ext = item.fileExtension
            let destinationURL = await storageService.createTempFilePath(extension: ext)
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempLocalURL, to: destinationURL)
            
            return destinationURL
            
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Download Delegate

/// ダウンロード進捗を追跡するデリゲート
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: @Sendable (Double) -> Void
    private let expectedContentLength: Int64
    
    init(
        expectedContentLength: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) {
        self.expectedContentLength = expectedContentLength
        self.progressHandler = progressHandler
        super.init()
    }
    
    // ダウンロード進捗
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedContentLength
        guard total > 0 else { return }
        
        let progress = Double(totalBytesWritten) / Double(total)
        progressHandler(min(progress, 1.0))
    }
    
    // ダウンロード完了
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // URLSession.download(for:)が処理するため、ここでは何もしない
    }
}

// MARK: - Errors

enum DownloaderError: LocalizedError {
    case downloadFailed
    case httpError
    case extractionFailed
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "ダウンロードに失敗しました"
        case .httpError:
            return "サーバーエラーが発生しました"
        case .extractionFailed:
            return "解凍に失敗しました"
        }
    }
}
