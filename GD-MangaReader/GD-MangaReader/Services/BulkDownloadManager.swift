// BulkDownloadManager.swift
// GD-MangaReader
//
// 一括ダウンロード処理を管理するマネージャー

import Foundation
import GoogleAPIClientForREST_Drive
import SwiftUI

/// 一括ダウンロード全体の進行状態を管理
@MainActor
@Observable
final class BulkDownloadManager {
    static let shared = BulkDownloadManager()
    
    // MARK: - Properties
    
    private(set) var isDownloading: Bool = false
    private(set) var currentCount: Int = 0
    private(set) var totalCount: Int = 0
    private(set) var targetFolderId: String?
    
    var onDownloadUpdate: (() -> Void)?
    
    private init() {}
    
    // MARK: - Methods
    
    /// 指定フォルダ内のZIP/アーカイブを一括処理
    func downloadSeries(
        folder: DriveItem,
        driveService: DriveService,
        authorizer: (any GTMSessionFetcherAuthorizer)?,
        accessToken: String?,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard !isDownloading else { return }
        isDownloading = true
        targetFolderId = folder.id
        currentCount = 0
        totalCount = 0
        
        Task {
            defer {
                resetState()
            }
            
            do {
                // 1. フォルダ内の全ファイルを取得（再帰ではなくフラットな一覧）
                var allItems: [DriveItem] = []
                var token: String? = nil
                repeat {
                    let result = try await driveService.listFiles(in: folder.id, pageToken: token)
                    allItems.append(contentsOf: result.items)
                    token = result.nextPageToken
                } while token != nil
                
                // 2. アーカイブのみ抽出
                let archives = allItems.filter { $0.isArchive }
                
                // 3. 未ダウンロードのものだけ抽出
                let pendingArchives = archives.filter { archive in
                    if let existing = try? LocalStorageService.shared.findComic(byDriveFileId: archive.id),
                       existing.status == .completed {
                        return false
                    }
                    return true
                }
                
                totalCount = pendingArchives.count
                
                if totalCount == 0 {
                    onComplete()
                    return
                }
                
                // 4. ダウンロード実行
                for archive in pendingArchives {
                    currentCount += 1
                    
                    let downloader = DownloaderViewModel(driveService: driveService)
                    downloader.configure(with: authorizer, accessToken: accessToken)
                    
                    // 個別のダウンロード＆解凍実行
                    _ = await downloader.downloadAndExtract(item: archive)
                    
                    onDownloadUpdate?()
                }
                
                onComplete()
                
            } catch {
                onError(error)
            }
        }
    }
    
    func resetState() {
        isDownloading = false
        currentCount = 0
        totalCount = 0
        targetFolderId = nil
    }
}
