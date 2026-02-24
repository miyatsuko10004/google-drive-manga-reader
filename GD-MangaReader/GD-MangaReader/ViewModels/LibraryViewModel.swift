// LibraryViewModel.swift
// GD-MangaReader
//
// Driveファイルブラウザの状態管理ViewModel

import Foundation
import SwiftUI

/// ライブラリ（Driveファイルブラウザ）の状態管理
@MainActor
@Observable
final class LibraryViewModel {
    // MARK: - Properties
    
    /// 現在表示中のアイテム一覧
    private(set) var items: [DriveItem] = []
    
    /// 読み込み中フラグ
    private(set) var isLoading: Bool = false
    
    /// エラーメッセージ
    private(set) var errorMessage: String?
    
    /// 現在のフォルダID（nilはルート）
    private(set) var currentFolderId: String? = Config.GoogleAPI.defaultFolderId
    
    /// フォルダ階層のパス（ナビゲーション用）
    private(set) var folderPath: [DriveItem] = []
    
    /// ダウンロード完了時のUI更新トリガー
    private(set) var downloadUpdateTrigger: Int = 0
    
    /// 次ページトークン（ページネーション用）
    private var nextPageToken: String?
    
    /// さらにアイテムがあるかどうか
    var hasMoreItems: Bool {
        nextPageToken != nil
    }
    
    /// 現在のフォルダ名
    var currentFolderName: String {
        folderPath.last?.name ?? "manga"
    }
    
    /// 表示モード
    enum ViewMode: String, CaseIterable {
        case grid = "グリッド"
        case list = "リスト"
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    var viewMode: ViewMode = .grid
    
    // MARK: - Dependencies
    
    // MARK: - Dependencies
    
    let driveService: DriveService
    
    // MARK: - Initialization
    
    // MARK: - Initialization
    
    init(driveService: DriveService? = nil) {
        let service = driveService ?? DriveService()
        self.driveService = service
        // 初期状態ではまだルートIDが確定していないためnilスタート
        // loadFiles()で確定させる
        self.currentFolderId = nil
    }
    
    // MARK: - Methods
    
    /// DriveServiceに認証情報を設定
    func configure(with authorizer: (any GTMFetcherAuthorizationProtocol)?) {
        guard let authorizer = authorizer else { return }
        driveService.configure(with: authorizer)
    }
    
    /// ファイル一覧を読み込み
    func loadFiles() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 現在のフォルダIDが未設定の場合、ルートIDを取得して設定
            if currentFolderId == nil {
                let rootId = try await driveService.fetchRootFolderId()
                currentFolderId = rootId
            }
            
            let result = try await driveService.listFiles(
                in: currentFolderId,
                pageToken: nil
            )
            items = result.items
            nextPageToken = result.nextPageToken
        } catch {
            errorMessage = error.localizedDescription
            // ルートフォルダが見つからない場合の特別なエラーハンドリングも検討可
        }
        
        isLoading = false
    }
    
    /// 次のページを読み込み
    func loadMoreFiles() async {
        guard hasMoreItems, !isLoading else { return }
        
        isLoading = true
        
        do {
            let result = try await driveService.listFiles(
                in: currentFolderId,
                pageToken: nextPageToken
            )
            items.append(contentsOf: result.items)
            nextPageToken = result.nextPageToken
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// フォルダに移動
    func navigateToFolder(_ folder: DriveItem) async {
        guard folder.isFolder else { return }
        
        folderPath.append(folder)
        
        currentFolderId = folder.id
        items = []
        await loadFiles()
    }
    
    /// 親フォルダに戻る
    func navigateBack() async {
        guard !folderPath.isEmpty else { return }
        
        folderPath.removeLast()
        
        if let parentFolder = folderPath.last {
            currentFolderId = parentFolder.id
        } else {
            // パスが空になったらルートIDに戻す
            currentFolderId = try? await driveService.fetchRootFolderId()
        }
        
        items = []
        await loadFiles()
    }
    
    /// ルートに戻る
    func navigateToRoot() async {
        folderPath = []
        // ルートIDを再取得（キャッシュされているはず）
        currentFolderId = try? await driveService.fetchRootFolderId()
        items = []
        await loadFiles()
    }
    
    /// リフレッシュ
    func refresh() async {
        await loadFiles()
    }
    
    /// 一括ダウンロード
    func bulkDownloadSeries(folder: DriveItem, authorizer: (any GTMFetcherAuthorizationProtocol)?, accessToken: String?) {
        Task {
            do {
                var allItems: [DriveItem] = []
                var token: String? = nil
                repeat {
                    let result = try await driveService.listFiles(in: folder.id, pageToken: token)
                    allItems.append(contentsOf: result.items)
                    token = result.nextPageToken
                } while token != nil
                
                let archives = allItems.filter { $0.isArchive }
                
                for archive in archives {
                    if let existing = try? LocalStorageService.shared.findComic(byDriveFileId: archive.id),
                       existing.status == .completed {
                        continue
                    }
                    
                    let downloader = DownloaderViewModel(driveService: driveService)
                    downloader.configure(with: authorizer, accessToken: accessToken)
                    _ = await downloader.downloadAndExtract(item: archive)
                    
                    self.downloadUpdateTrigger += 1
                }
            } catch {
                print("Bulk download error: \(error)")
            }
        }
    }
}

// MARK: - Import for GTMFetcherAuthorizationProtocol
import GoogleAPIClientForREST_Drive
