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
    var isOfflineMode: Bool = false {
        didSet {
            // オフラインへ切り替えたら進行中のサーバー検索をキャンセルして結果をクリアし、
            // オンラインへ戻したら（検索テキストがあれば）サーバー検索を再開する
            guard oldValue != isOfflineMode else { return }
            scheduleServerSearch()
        }
    }
    
    /// 現在表示中のアイテム一覧
    private(set) var items: [DriveItem] = []
    
    /// 読み込み中フラグ
    private(set) var isLoading: Bool = false
    
    /// エラーメッセージ
    private(set) var errorMessage: String?
    
    /// 検索テキスト
    var searchText: String = "" {
        didSet {
            updateFilteredItems()
            scheduleServerSearch()
        }
    }

    /// フィルタ・ソート済みの表示用アイテム一覧
    private(set) var filteredItems: [DriveItem] = []

    // MARK: - Server-side Search

    /// サーバーサイド検索（Drive全体）の結果。
    /// オンラインで検索テキストが入力されている間は、filteredItemsの代わりにこちらを表示する
    private(set) var searchResults: [DriveItem] = []

    /// サーバーサイド検索の実行中フラグ（「検索中...」表示用）
    private(set) var isSearching: Bool = false

    /// デバウンス付きのサーバー検索タスク（新しい入力が来るたびにキャンセルして張り直す）
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    /// サーバーサイド検索がアクティブかどうか。
    /// オフライン時は従来どおりローカル（読み込み済みアイテム）のみのフィルタで完結させる
    var isServerSearchActive: Bool {
        !isOfflineMode && !trimmedSearchText.isEmpty
    }

    /// 前後の空白を除いた検索テキスト
    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 一覧に表示するアイテム（サーバー検索中は検索結果、それ以外は現在フォルダのフィルタ結果）
    var displayItems: [DriveItem] {
        isServerSearchActive ? searchResults : filteredItems
    }
    
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
    /// rawValueはUserDefaultsへの永続化キーとして使うため、表示ラベルとは分離して
    /// 安定した識別子にしている（ラベル変更で保存済み設定が無効にならないようにする）
    enum SortOption: String, CaseIterable, Identifiable {
        case nameAsc
        case nameDesc
        case dateNewest
        case dateOldest

        var id: String { self.rawValue }

        /// UI表示用ラベル
        var label: String {
            switch self {
            case .nameAsc: return "名前 (A-Z)"
            case .nameDesc: return "名前 (Z-A)"
            case .dateNewest: return "追加日 (新しい順)"
            case .dateOldest: return "追加日 (古い順)"
            }
        }
    }

    var sortOption: SortOption = .nameAsc {
        didSet {
            // init中の復元代入では副作用（再保存・フィルタ更新）を起こさない
            // （下記isRestoringPreferencesのコメント参照）
            guard !isRestoringPreferences else { return }
            userDefaults.set(sortOption.rawValue, forKey: Self.sortOptionDefaultsKey)
            updateFilteredItems()
        }
    }

    /// 表示モード
    /// rawValueはUserDefaultsへの永続化キー（SortOptionと同じ方針）
    enum ViewMode: String, CaseIterable {
        case grid
        case list

        /// UI表示用ラベル
        var label: String {
            switch self {
            case .grid: return "グリッド"
            case .list: return "リスト"
            }
        }

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    var viewMode: ViewMode = .grid {
        didSet {
            // init中の復元代入では副作用（再保存）を起こさない
            // （下記isRestoringPreferencesのコメント参照）
            guard !isRestoringPreferences else { return }
            userDefaults.set(viewMode.rawValue, forKey: Self.viewModeDefaultsKey)
        }
    }

    // MARK: - Persistence

    /// ソート順・表示モードの永続化キー
    static let sortOptionDefaultsKey = "library.sortOption"
    static let viewModeDefaultsKey = "library.viewMode"

    private let userDefaults: UserDefaults

    /// init中の設定復元でdidSetの副作用を抑止するフラグ。
    /// @Observableマクロは格納プロパティをアクセサ付きに書き換えるため、
    /// 通常のSwiftクラスと異なり、initでの代入でもdidSetが発火する。
    /// このフラグがないと、復元のたびに同じ値をUserDefaultsへ書き戻し、
    /// updateFilteredItems()を呼んでしまう（現状は無害だが、didSetに
    /// 副作用が増えた場合の地雷になるため明示的に抑止する）。
    private var isRestoringPreferences = false
    
    // MARK: - Dependencies
    
    let driveService: DriveService
    
    // MARK: - Initialization
    
    init(driveService: DriveService? = nil, userDefaults: UserDefaults = .standard) {
        let service = driveService ?? DriveService()
        self.driveService = service
        self.userDefaults = userDefaults
        // 初期状態ではまだルートIDが確定していないためnilスタート
        // loadFiles()で確定させる
        self.currentFolderId = nil

        // 保存済みのソート順・表示モードを復元（未保存・不正値はデフォルトのまま）。
        // @Observableではinit中の代入でもdidSetが発火するため、フラグで副作用を抑止する
        isRestoringPreferences = true
        if let saved = userDefaults.string(forKey: Self.sortOptionDefaultsKey),
           let option = SortOption(rawValue: saved) {
            self.sortOption = option
        }
        if let saved = userDefaults.string(forKey: Self.viewModeDefaultsKey),
           let mode = ViewMode(rawValue: saved) {
            self.viewMode = mode
        }
        isRestoringPreferences = false
    }
    
    // MARK: - Methods
    
    /// 最新のアイテム、検索テキスト、ソート順に応じたフィルタリング結果を更新
    private func updateFilteredItems() {
        // 先に検索キーワードで絞り込むことで、ソート（O(N log N)処理）の対象件数を減らすパフォーマンス最適化
        let targetItems = searchText.isEmpty
            ? items
            : items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        filteredItems = sortItems(targetItems)
        // ソート順変更をサーバー検索結果にも反映する（sortOptionのdidSetからも呼ばれるため）
        searchResults = sortItems(searchResults)
    }

    /// 現在のソート順でアイテムをソートする
    private func sortItems(_ items: [DriveItem]) -> [DriveItem] {
        items.sorted {
            switch sortOption {
            case .nameAsc: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case .nameDesc: return $0.name.localizedStandardCompare($1.name) == .orderedDescending
            case .dateNewest: return ($0.createdTime ?? .distantPast) > ($1.createdTime ?? .distantPast)
            case .dateOldest: return ($0.createdTime ?? .distantPast) < ($1.createdTime ?? .distantPast)
            }
        }
    }

    /// サーバーサイド検索をデバウンス（300ms）付きでスケジュールする。
    /// 検索テキストが空になった／オフラインの場合は結果をクリアして通常表示に戻す
    private func scheduleServerSearch() {
        searchTask?.cancel()

        let query = trimmedSearchText
        guard !isOfflineMode, !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            // デバウンス: 連続入力中はキャンセルされ、最後の入力から300ms後にのみ実行される
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }

            do {
                // 検索対象は現在フォルダではなくDrive全体（制限の詳細はDriveService.searchFiles参照）。
                // ページネーションは行わず先頭ページ（最大50件）のみ表示する
                let result = try await self.driveService.searchFiles(query: query)
                guard !Task.isCancelled else { return }
                self.searchResults = self.sortItems(result.items)
                self.isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                // サーバー検索に失敗した場合は、読み込み済みアイテムのローカルフィルタ結果へ
                // フォールバックする（フォルダ一覧ごとエラー画面に置き換えるのは過剰なため）。
                // filteredItemsは未トリムのsearchTextで絞り込むため、サーバーと同じ
                // トリム済みqueryでフィルタし直す（" Naruto "等で結果が消えないように）
                self.searchResults = self.sortItems(
                    self.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
                )
                self.isSearching = false
            }
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
        
        // recentlyRead の各コミックに対するシリーズ名をキャッシュ
        let recentlyReadWithTitles = recentlyRead.compactMap { comic -> (LocalComic, String)? in
            let title = extractSeriesTitle(from: comic.title)
            return title.isEmpty ? nil : (comic, title)
        }

        // 対象となるシリーズ名を抽出
        let targetSeriesTitles = Set(recentlyReadWithTitles.map { $0.1 })

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

        for (comic, seriesTitle) in recentlyReadWithTitles {
            guard !seenSeries.contains(seriesTitle) else { continue }
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
    
    private static let seriesTitleBracketRegex = try! NSRegularExpression(pattern: #"\s*[\(\[\{].*?[\)\]\}]$"#, options: .caseInsensitive)
    private static let seriesTitleVolumeRegex = try! NSRegularExpression(pattern: #"\s*(?:vol\.?|#|第)?\s*\d+(?:\s*[巻回話])?.*$"#, options: .caseInsensitive)

    /// タイトルからシリーズ名を抽出（巻数などを除去）
    private func extractSeriesTitle(from title: String) -> String {
        var result = title

        let range1 = NSRange(result.startIndex..<result.endIndex, in: result)
        if let match = Self.seriesTitleBracketRegex.firstMatch(in: result, range: range1),
           let matchRange = Range(match.range, in: result) {
            result = String(result[..<matchRange.lowerBound])
        }

        let range2 = NSRange(result.startIndex..<result.endIndex, in: result)
        if let match = Self.seriesTitleVolumeRegex.firstMatch(in: result, range: range2),
           let matchRange = Range(match.range, in: result) {
            result = String(result[..<matchRange.lowerBound])
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

        // 検索結果からフォルダを開いた場合は検索を解除し、通常のフォルダ表示に戻す
        // （didSet経由でサーバー検索タスクのキャンセルと結果クリアも行われる）
        if !searchText.isEmpty {
            searchText = ""
        }

        // サーバー検索の結果はDrive全体から来るため、現在フォルダの子とは限らない。
        // 現在フォルダの子でないフォルダを開く場合、古いパンくずに追記すると
        // 「A > B > （Cの下にある）Naruto」のような偽の階層ができ、navigateBackが
        // 誤った場所（B）へ戻ってしまう。そのため検索経由の遷移では既存のローカルな
        // パンくずを破棄してそのフォルダから始める（実際の祖先パスの再構築は
        // APIコールが必要でコストが高いため、スコープ外とする）
        if folder.parentId != currentFolderId {
            folderPath = [folder]
        } else {
            folderPath.append(folder)
        }
        
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
    
    /// 中間フォルダに直接ジャンプする
    func navigateToIntermediateFolder(_ folder: DriveItem) async {
        guard !isOfflineMode else { return }
        guard let index = folderPath.firstIndex(where: { $0.id == folder.id }) else { return }

        // 指定されたフォルダ以降のパスを削除
        folderPath = Array(folderPath.prefix(through: index))

        currentFolderId = folder.id
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
