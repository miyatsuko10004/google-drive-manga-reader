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

    mutating func removeValue(forKey key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        dict.removeValue(forKey: key)
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
    
    /// オフラインモードが有効かどうか
    var isOfflineMode: Bool = false
    
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
        didSet {
            updateRecentComics()
            updateNextRecommendedComics()
        }
    }
    
    /// 最近読んだコミック（キャッシュから抽出して降順でソート、最大5件）
    private(set) var recentComics: [LocalComic] = []
    
    /// 次に読むべきおすすめ（最近読んだ作品の次巻など）
    private(set) var nextRecommendedComics: [LocalComic] = []
    
    /// シリーズ（フォルダ）の永続サムネイルURL解決結果のメモリ前段キャッシュ (LRU管理, 上限500件)
    /// 実体（ディスクキャッシュ）は`SeriesThumbnailStore`が保持し、これは毎スクロールでの
    /// ディスクI/Oを避けるための前段に過ぎないため、`loadFiles()`等では破棄しない
    private(set) var seriesThumbnails = LRUCache<String, URL?>(capacity: 500)
    
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
    
    /// 次に読むべきおすすめを更新
    private func updateNextRecommendedComics() {
        let allComics = Array(downloadedComics.values)
        guard !allComics.isEmpty else {
            nextRecommendedComics = []
            return
        }
        
        // 最近読んだ順に数件のシリーズを対象にする
        let recentlyRead = allComics
            .filter { $0.lastReadAt != nil }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
            .prefix(5)
            
        var recommendations: [LocalComic] = []
        var seenSeries = Set<String>()
        
        // 対象となるシリーズ名を事前に抽出
        let targetSeriesTitles = Set(recentlyRead.compactMap { comic -> String? in
            let title = extractSeriesTitle(from: comic.title)
            return title.isEmpty ? nil : title
        })

        // 対象シリーズのみに絞ってグルーピング
        var seriesGroups: [String: [LocalComic]] = [:]
        if !targetSeriesTitles.isEmpty {
            for comic in allComics {
                let title = extractSeriesTitle(from: comic.title)
                if targetSeriesTitles.contains(title) {
                    seriesGroups[title, default: []].append(comic)
                }
            }
        }

        for comic in recentlyRead {
            let seriesTitle = extractSeriesTitle(from: comic.title)
            guard !seriesTitle.isEmpty && !seenSeries.contains(seriesTitle) else { continue }
            seenSeries.insert(seriesTitle)
            
            // このシリーズの全巻を取得してソート
            let seriesVolumes = (seriesGroups[seriesTitle] ?? [])
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            
            // 現在の巻のインデックスを探す
            if let currentIndex = seriesVolumes.firstIndex(where: { $0.id == comic.id }) {
                // 次の巻があれば追加
                if currentIndex + 1 < seriesVolumes.count {
                    let nextVol = seriesVolumes[currentIndex + 1]
                    // まだ読み終わっていない（進捗100%未満）ものを追加
                    if nextVol.readingProgress < 0.95 {
                        recommendations.append(nextVol)
                    }
                }
            }
        }
        
        nextRecommendedComics = recommendations
    }
    
    /// タイトルからシリーズ名を抽出（巻数などを除去）
    private func extractSeriesTitle(from title: String) -> String {
        // 数字や巻数表記を簡易的に除去
        let patterns = [
            #"\s*[\(\[\{].*?[\)\]\}]$"#, // 末尾の括弧内を除去
            #"\s*(?:vol\.?|#|第)?\s*\d+(?:\s*[巻回話])?.*$"# // 巻数表記を除去
        ]
        
        var result = title
        for pattern in patterns {
            if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                result = String(result[..<range.lowerBound])
            }
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }
    
    /// DriveServiceに認証情報を設定
    func configure(with authorizer: (any GTMSessionFetcherAuthorizer)?) {
        guard let authorizer = authorizer else { return }
        driveService.configure(with: authorizer)
    }
    
    /// ファイル一覧を読み込み
    func loadFiles() async {
        refreshDownloadedComics()
        isLoading = true
        errorMessage = nil
        
        if isOfflineMode {
            self.folderPath = []
            self.currentFolderId = nil
            let localComics = (try? LocalStorageService.shared.loadComics()) ?? []
            self.items = localComics
                .filter { $0.status == .completed }
                .map { DriveItem(from: $0) }
            updateFilteredItems()
            self.nextPageToken = nil
            self.isLoading = false
            return
        }
        
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
    
    /// シリーズ（フォルダ）の永続サムネイルを解決する
    /// ディスクキャッシュ（1巻ダウンロード時に生成済み）があればそれを、なければ
    /// Driveの1巻候補（自然順で先頭）の低画質thumbnailLinkにフォールバックする
    func resolveSeriesThumbnail(for folder: DriveItem) async {
        guard folder.isFolder else { return }
        // 既に前段キャッシュにのっていれば何もしない
        guard seriesThumbnails[folder.id] == nil else { return }

        if let diskURL = SeriesThumbnailStore.shared.cachedThumbnailURL(forFolderId: folder.id) {
            seriesThumbnails.set(diskURL, forKey: folder.id)
            return
        }

        do {
            let firstVolume = try await driveService.fetchArchivesNaturalSorted(inFolder: folder.id).first
            seriesThumbnails.set(firstVolume?.thumbnailURL, forKey: folder.id)
        } catch {
            print("Series Thumbnail Fetch Error: \(folder.name) - \(error.localizedDescription)")
            // 一時的なネットワーク/API エラーの場合はキャッシュせず、次回の表示時に再試行させる
            // （「1巻が存在しない/thumbnailURLがない」という確定結果のみnilでキャッシュする）
        }
    }

    /// 指定フォルダの前段キャッシュを無効化する（ダウンロード完了で新しいディスクキャッシュが
    /// 生成された際に、次回`resolveSeriesThumbnail`でそれを拾わせるため）
    func invalidateSeriesThumbnail(folderId: String) {
        seriesThumbnails.removeValue(forKey: folderId)
    }

    /// 全シリーズの前段キャッシュを無効化する（ストレージ全削除後、消したファイルのURLを
    /// 表示に使い続けてしまわないようにするため）
    func invalidateAllSeriesThumbnails() {
        seriesThumbnails.removeAll()
    }
    
    /// 次のページを読み込み
    func loadMoreFiles() async {
        guard !isOfflineMode else { return }
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
        guard !isOfflineMode else { return }
        guard folder.isFolder else { return }
        
        folderPath.append(folder)
        
        currentFolderId = folder.id
        items = []
        updateFilteredItems()
        await loadFiles()
    }
    
    /// 親フォルダに戻る
    func navigateBack() async {
        guard !isOfflineMode else { return }
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
        guard !isOfflineMode else { return }
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
}

// MARK: - Import for GTMFetcherAuthorizationProtocol
import GoogleAPIClientForREST_Drive
