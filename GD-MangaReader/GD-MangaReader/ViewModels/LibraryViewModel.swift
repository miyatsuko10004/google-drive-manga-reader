// LibraryViewModel.swift
// GD-MangaReader
//
// Driveファイルブラウザの状態管理ViewModel

import Foundation
import SwiftUI

/// 簡易的なLRUキャッシュ（Viewからの読み取りを安全に行うため、非破壊なsubscriptを提供）
struct LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var order: [Key] = []
    private var dict: [Key: Value] = [:]
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    mutating func set(_ value: Value, forKey key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
        dict[key] = value
        
        if order.count > capacity {
            let oldest = order.removeFirst()
            dict.removeValue(forKey: oldest)
        }
    }
    
    mutating func removeAll() {
        dict.removeAll()
        order.removeAll()
    }
    
    // Viewバインディング用に非破壊な読み取りを提供（順序の更新は行わない）
    subscript(key: Key) -> Value? {
        dict[key]
    }
}

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
    
    /// 検索テキスト
    var searchText: String = "" {
        didSet { updateFilteredItems() }
    }
    
    /// フィルタ・ソート済みの表示用アイテム一覧
    private(set) var filteredItems: [DriveItem] = []
    
    // MARK: - Local Cache
    
    /// ダウンロード済みコミックのキャッシュ (DriveFileId -> LocalComic)
    private(set) var downloadedComics: [String: LocalComic] = [:] {
        didSet { updateRecentComics() }
    }
    
    /// 最近読んだコミック（キャッシュから抽出して降順でソート、最大5件）
    private(set) var recentComics: [LocalComic] = []
    
    /// フォルダのサムネイルURLキャッシュ (LRU管理, 上限500件)
    private(set) var folderThumbnails = LRUCache<String, [URL]>(capacity: 500)
    
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
        didSet { updateFilteredItems() }
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
    
    let driveService: DriveService
    
    // MARK: - Initialization
    
    init(driveService: DriveService? = nil) {
        let service = driveService ?? DriveService()
        self.driveService = service
        // 初期状態ではまだルートIDが確定していないためnilスタート
        // loadFiles()で確定させる
        self.currentFolderId = nil
    }
    
    // MARK: - Methods
    
    /// 最新のアイテム、検索テキスト、ソート順に応じたフィルタリング結果を更新
    private func updateFilteredItems() {
        let sorted = items.sorted {
            switch sortOption {
            case .nameAsc: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case .nameDesc: return $0.name.localizedStandardCompare($1.name) == .orderedDescending
            case .dateNewest: return ($0.createdTime ?? .distantPast) > ($1.createdTime ?? .distantPast)
            case .dateOldest: return ($0.createdTime ?? .distantPast) < ($1.createdTime ?? .distantPast)
            }
        }
        
        if searchText.isEmpty {
            filteredItems = sorted
        } else {
            filteredItems = sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    /// 最近読んだコミックリストを更新
    private func updateRecentComics() {
        recentComics = Array(
            downloadedComics.values
                .filter { $0.lastReadAt != nil }
                .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
                .prefix(5)
        )
    }
    
    /// DriveServiceに認証情報を設定
    func configure(with authorizer: (any GTMSessionFetcherAuthorizer)?) {
        guard let authorizer = authorizer else { return }
        driveService.configure(with: authorizer)
    }
    
    /// ファイル一覧を読み込み
    func loadFiles() async {
        refreshDownloadedComics()
        folderThumbnails.removeAll()
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
            updateFilteredItems()
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
            folderThumbnails.set(urls, forKey: folder.id)
            
        } catch {
            print("Folder Thumbnail Fetch Array Error: \(folder.name) - \(error.localizedDescription)")
            // 失敗時は空配列を入れて無限リトライを防止
            folderThumbnails.set([], forKey: folder.id)
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
            updateFilteredItems()
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
        updateFilteredItems()
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
        updateFilteredItems()
        await loadFiles()
    }
    
    /// ルートに戻る
    func navigateToRoot() async {
        folderPath = []
        // ルートIDを再取得（キャッシュされているはず）
        currentFolderId = try? await driveService.fetchRootFolderId()
        items = []
        updateFilteredItems()
        await loadFiles()
    }
    
    /// リフレッシュ
    func refresh() async {
        await loadFiles()
    }
    
    /// 一括ダウンロード
    func bulkDownloadSeries(folder: DriveItem, authorizer: (any GTMSessionFetcherAuthorizer)?, accessToken: String?) {
        let manager = BulkDownloadManager.shared
        manager.onDownloadUpdate = { [weak self] in
            Task { @MainActor in
                self?.refreshDownloadedComics()
                self?.downloadUpdateTrigger += 1
            }
        }
        
        manager.downloadSeries(
            folder: folder,
            driveService: driveService,
            authorizer: authorizer,
            accessToken: accessToken,
            onComplete: {
                // Handle completion
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "一括ダウンロード中にエラーが発生しました: \(error.localizedDescription)"
                }
            }
        )
    }
}

// MARK: - Import for GTMFetcherAuthorizationProtocol
import GoogleAPIClientForREST_Drive
