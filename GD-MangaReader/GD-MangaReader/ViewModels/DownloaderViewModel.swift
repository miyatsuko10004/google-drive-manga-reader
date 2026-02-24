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
    /// DownloadSheetから既存コミック検出時に.completedを設定するためinternal(set)
    internal(set) var status: DownloadStatus = .pending
    
    /// フォルダダウンロードモードかどうか
    private var isFolderDownload: Bool = false
    
    /// エラーメッセージ
    private(set) var errorMessage: String?
    
    /// 処理中のファイル名
    private(set) var currentFileName: String?
    
    /// 処理中かどうか
    var isProcessing: Bool {
        status == .downloading || status == .extracting
    }
    
    /// 合計進捗
    var totalProgress: Double {
        switch status {
        case .pending:
            return 0
        case .downloading:
            return isFolderDownload ? downloadProgress : downloadProgress * 0.5
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
    
    init(driveService: DriveService? = nil) {
        self.driveService = driveService ?? DriveService()
    }
    
    // MARK: - Public Methods
    
    /// DriveServiceに認証情報を設定
    func configure(with authorizer: (any GTMFetcherAuthorizationProtocol)?, accessToken: String?) {
        guard let authorizer = authorizer else { return }
        driveService.configure(with: authorizer)
        driveService.setAccessToken(accessToken)
    }
    
    /// ファイルをダウンロード・解凍してLocalComicを作成
    func downloadAndExtract(item: DriveItem) async -> LocalComic? {
        reset()
        currentFileName = item.name
        
        do {
            // 既にダウンロード済みかチェック
            if let existingComic = try storageService.findComic(byDriveFileId: item.id) {
                if existingComic.status == .completed {
                    status = .completed
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
            let comicDirectory = try storageService.createComicDirectory(name: item.name)
            
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
            storageService.deleteTempFile(at: tempFileURL)
            
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
            
            try storageService.addComic(comic)
            
            status = .completed
            return comic
            
            
        } catch {
            status = .failed
            errorMessage = error.localizedDescription
            return nil
        }
    }
    
    /// フォルダ内の画像をダウンロードしてLocalComicを作成
    func downloadFolder(folderId: String, folderName: String) async -> LocalComic? {
        reset()
        isFolderDownload = true
        currentFileName = folderName
        
        do {
            // 既にダウンロード済みかチェック
            if let existingComic = try storageService.findComic(byDriveFileId: folderId) {
                if existingComic.status == .completed {
                    status = .completed
                    return existingComic
                }
            }
            
            // 1. 画像一覧取得
            status = .downloading
            let images = try await driveService.listImages(in: folderId)
            
            guard !images.isEmpty else {
                errorMessage = "フォルダ内に画像が見つかりませんでした"
                status = .failed
                return nil
            }
            
            // 2. ディレクトリ作成
            let comicDirectory = try storageService.createComicDirectory(name: folderName)
            
            // 3. 画像を順次ダウンロード
            var savedFileNames: [String] = []
            let totalCount = Double(images.count)
            
            for (index, image) in images.enumerated() {
                currentFileName = "\(folderName) (\(index + 1)/\(images.count))"
                
                // 個別ファイルのダウンロード
                guard let tempURL = await downloadFile(item: image) else {
                    // ダウンロード失敗時はエラーとする
                    throw DownloaderError.downloadFailed
                }
                
                // 保存先に移動
                let destinationURL = comicDirectory.appendingPathComponent(image.name)
                // 既存ファイルがあれば削除
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                savedFileNames.append(image.name)
                
                // 進捗更新
                let progress = Double(index + 1) / totalCount
                downloadProgress = progress
            }
            
            // ファイル名でソート
            savedFileNames.sort()
            
            // 4. LocalComic作成・保存
            let localPath = comicDirectory.lastPathComponent
            let comic = LocalComic(
                title: folderName,
                driveFileId: folderId,
                localPath: localPath,
                imageFileNames: savedFileNames,
                originalFileSize: nil, // フォルダサイズは不明
                status: .completed
            )
            
            try storageService.addComic(comic)
            
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
        isFolderDownload = false
    }
    
    // MARK: - Private Methods
    
    /// ファイルをダウンロード
    private func downloadFile(item: DriveItem) async -> URL? {
        do {
            let request = try await driveService.getDownloadRequest(for: item.id)
            let expectedSize = item.size ?? 0
            
            return try await withCheckedThrowingContinuation { continuation in
                let delegate = DownloadDelegate(
                    expectedContentLength: expectedSize,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress = progress
                        }
                    },
                    completionHandler: { result in
                    switch result {
                    case .success(let (tempURL, response)):
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200...299).contains(httpResponse.statusCode) else {
                            if FileManager.default.fileExists(atPath: tempURL.path) {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            continuation.resume(throwing: DownloaderError.httpError)
                            return
                        }
                        
                        do {
                            let ext = item.fileExtension
                            let destinationURL = LocalStorageService.shared.createTempFilePath(extension: ext)
                            
                            let fileManager = FileManager.default
                            if fileManager.fileExists(atPath: destinationURL.path) {
                                try fileManager.removeItem(at: destinationURL)
                            }
                            try fileManager.moveItem(at: tempURL, to: destinationURL)
                            // tempURL is successfully moved, no need to delete
                            continuation.resume(returning: destinationURL)
                        } catch {
                            if FileManager.default.fileExists(atPath: tempURL.path) {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                })
                
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                delegate.session = session // Retain session internally to invalidate later
                let task = session.downloadTask(with: request)
                task.resume()
            }
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
    private let completionHandler: (Result<(URL, URLResponse), Error>) -> Void
    private let expectedContentLength: Int64
    var session: URLSession?
    
    init(
        expectedContentLength: Int64,
        progressHandler: @escaping @Sendable (Double) -> Void,
        completionHandler: @escaping (Result<(URL, URLResponse), Error>) -> Void
    ) {
        self.expectedContentLength = expectedContentLength
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedContentLength
        guard total > 0 else { return }
        
        // Sometimes total isn't accurate if compressed, cap at 1.0 but don't stick to 0
        let progress = Double(totalBytesWritten) / Double(total)
        progressHandler(min(progress, 1.0))
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response {
            // Because location is temporary, we must move/copy it before returning or use it immediately.
            // Using continuation in completion handler requires temp file to be valid.
            // URLSession removes the file after this method returns. So we move it here first.
            let tempDir = FileManager.default.temporaryDirectory
            let uniqueURL = tempDir.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.moveItem(at: location, to: uniqueURL)
                completionHandler(.success((uniqueURL, response)))
            } catch {
                completionHandler(.failure(error))
            }
        } else {
            completionHandler(.failure(DownloaderError.downloadFailed))
        }
        self.session?.invalidateAndCancel()
        self.session = nil
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            completionHandler(.failure(error))
            self.session?.invalidateAndCancel()
            self.session = nil
        }
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
