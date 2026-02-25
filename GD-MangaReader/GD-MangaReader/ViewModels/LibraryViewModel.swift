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
    
    // MARK: - Local Cache
    
    /// ダウンロード済みコミックのキャッシュ (DriveFileId -> LocalComic)
    private(set) var downloadedComics: [String: LocalComic] = [:]
    
    /// フォルダのサムネイルURLキャッシュ (FolderId -> [URL]) (最大4つ)
    private(set) var folderThumbnails: [String: [URL]] = [:]
    
    /// 現在のフォルダID（nilはルート）
    private(set) var currentFolderId: String? = Config.GoogleAPI.defaultFolderId
    
    /// フォルダ階層のパス（ナビゲーション用）
    private(set) var folderPath: [DriveItem] = []
    
    /// ダウンロード完了時のUI更新トリガー
    private(set) var downloadUpdateTrigger: Int = 0
    
    // MARK: - Bulk Download Progress State
    
    /// 一括ダウンロード実行中フラグ
    private(set) var isBulkDownloading: Bool = false
    
    /// 現在ダウンロード中の件数 (1-based index)
    private(set) var bulkDownloadCurrent: Int = 0
    
    /// 一括ダウンロードする合計件数
    private(set) var bulkDownloadTotal: Int = 0
    
    /// 一括ダウンロードの対象フォルダID (UI表示用)
    private(set) var bulkDownloadTargetFolderId: String?
    
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
    
    // MARK: - Sorting and View Mode
    
    /// ソートオプション
    enum SortOption: String, CaseIterable, Identifiable {
        case nameAsc = "名前 (A-Z)"
        case nameDesc = "名前 (Z-A)"
        case dateNewest = "追加日 (新しい順)"
        case dateOldest = "追加日 (古い順)"
        
        var id: String { self.rawValue }
    }
    
    var sortOption: SortOption = .nameAsc {
        didSet {
            sortItems()
        }
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
        refreshDownloadedComics()
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
            sortItems()
            nextPageToken = result.nextPageToken
        } catch {
            errorMessage = error.localizedDescription
            // ルートフォルダが見つからない場合の特別なエラーハンドリングも検討可
        }
        
        isLoading = false
    }
    
    /// ダウンロード済みコミックリストを更新
    func refreshDownloadedComics() {
        if let comics = try? LocalStorageService.shared.loadComics() {
            var newCache: [String: LocalComic] = [:]
            for comic in comics where comic.status == .completed {
                newCache[comic.driveFileId] = comic
            }
            downloadedComics = newCache
        }
    }
    
    /// フォルダ用のプレビューサムネイル（最大4件）を非同期取得してキャッシュする
    func fetchThumbnails(for folder: DriveItem) async {
        guard folder.isFolder else { return }
        // 既にローカルキャッシュにのっていれば何もしない
        guard folderThumbnails[folder.id] == nil else { return }
        
        do {
            let candidates = try await driveService.fetchThumbnailCandidates(forFolder: folder.id, limit: 4)
            var urls: [URL] = []
            
            for candidate in candidates {
                // 1. ローカルに高画質キャッシュがあるか
                if let localComic = downloadedComics[candidate.id],
                   let firstImage = localComic.imagePaths.first {
                    urls.append(firstImage)
                }
                // 2. DriveAPIによる低画質サムネイルがあるか
                else if let thumb = candidate.thumbnailURL {
                    urls.append(thumb)
                }
            }
            
            // 4件に満たない場合でもキャッシュを確定して再フェッチを防ぐ
            folderThumbnails[folder.id] = urls
            
        } catch {
            print("Folder Thumbnail Fetch Array Error: \(folder.name) - \(error.localizedDescription)")
            // 失敗時は空配列を入れて無限リトライを防止
            folderThumbnails[folder.id] = []
        }
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
            sortItems()
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
    
    /// アイテムをソートする
    private func sortItems() {
        items.sort { lhs, rhs in
            switch sortOption {
            case .nameAsc:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDesc:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .dateNewest:
                return (lhs.modifiedTime ?? Date.distantPast) > (rhs.modifiedTime ?? Date.distantPast)
            case .dateOldest:
                return (lhs.modifiedTime ?? Date.distantPast) < (rhs.modifiedTime ?? Date.distantPast)
            }
        }
    }
    
    /// リフレッシュ
    func refresh() async {
        await loadFiles()
    }
    
    /// 一括ダウンロード
    func bulkDownloadSeries(folder: DriveItem, authorizer: (any GTMFetcherAuthorizationProtocol)?, accessToken: String?) {
        // 多重起動防止
        guard !isBulkDownloading else { return }
        
        // Task起動前にフラグを立てることで、連続タップによる複数実行（競合）を防止
        isBulkDownloading = true
        
        Task {
            defer {
                resetBulkDownloadState()
            }
            
            bulkDownloadTargetFolderId = folder.id
            bulkDownloadCurrent = 0
            bulkDownloadTotal = 0
            
            do {
                var allItems: [DriveItem] = []
                var token: String? = nil
                repeat {
                    let result = try await driveService.listFiles(in: folder.id, pageToken: token)
                    allItems.append(contentsOf: result.items)
                    token = result.nextPageToken
                } while token != nil
                
                let archives = allItems.filter { $0.isArchive }
                
                // 未ダウンロードのものだけ抽出
                let pendingArchives = archives.filter { archive in
                    if let existing = try? LocalStorageService.shared.findComic(byDriveFileId: archive.id),
                       existing.status == .completed {
                        return false
                    }
                    return true
                }
                
                bulkDownloadTotal = pendingArchives.count
                
                if bulkDownloadTotal == 0 {
                    // 全てダウンロード済み
                    return
                }
                
                for archive in pendingArchives {
                    bulkDownloadCurrent += 1
                    
                    let downloader = DownloaderViewModel(driveService: driveService)
                    downloader.configure(with: authorizer, accessToken: accessToken)
                    _ = await downloader.downloadAndExtract(item: archive)
                    
                    self.refreshDownloadedComics()
                    self.downloadUpdateTrigger += 1
                }
            } catch {
                errorMessage = "一括ダウンロード中にエラーが発生しました: \(error.localizedDescription)"
                print("Bulk download error: \(error)")
            }
        }
    }
    
    private func resetBulkDownloadState() {
        isBulkDownloading = false
        bulkDownloadCurrent = 0
        bulkDownloadTotal = 0
        bulkDownloadTargetFolderId = nil
    }
}

// MARK: - Import for GTMFetcherAuthorizationProtocol
import GoogleAPIClientForREST_Drive
