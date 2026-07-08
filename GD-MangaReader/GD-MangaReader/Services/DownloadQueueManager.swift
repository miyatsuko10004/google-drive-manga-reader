// DownloadQueueManager.swift
// GD-MangaReader
//
// バックグラウンドダウンロードキューの管理
// 画面を閉じてもダウンロードを継続し、複数のダウンロードをキューで直列/並列管理する

import Foundation
import SwiftUI
import UIKit
import GoogleAPIClientForREST_Drive

// MARK: - Download Queue Task

/// ダウンロードキュー内の1タスク
@MainActor
@Observable
final class DownloadQueueTask: Identifiable {
    /// タスクの状態
    enum State: Equatable {
        /// 待機中
        case queued
        /// 実行中（ダウンロード・解凍）
        case running
        /// 完了
        case completed
        /// 失敗
        case failed(String)
        /// キャンセル済み
        case cancelled

        /// 終了状態かどうか
        var isFinished: Bool {
            switch self {
            case .completed, .failed, .cancelled: return true
            case .queued, .running: return false
            }
        }
    }

    let id = UUID()

    /// ダウンロード対象
    let target: DownloadTarget

    /// 対象の親フォルダID（フォルダ単位のインジケーター表示用）
    let parentFolderId: String?

    /// 現在の状態
    fileprivate(set) var state: State = .queued

    /// 実行中のダウンローダー（進捗参照用）
    fileprivate(set) var downloader: DownloaderViewModel?

    /// 完了時の成果物
    fileprivate(set) var comic: LocalComic?

    /// 実行中のSwift Task
    fileprivate var runner: Task<Void, Never>?

    /// キャンセル要求済みフラグ
    fileprivate var cancelRequested = false

    init(target: DownloadTarget) {
        self.target = target
        if case .file(let item) = target {
            self.parentFolderId = item.parentId
        } else {
            self.parentFolderId = nil
        }
    }

    /// 対象のDriveファイルID
    var driveFileId: String {
        switch target {
        case .file(let item): return item.id
        case .folder(let id, _): return id
        }
    }

    /// 表示名
    var name: String { target.name }

    /// 進捗（0.0〜1.0）
    var progress: Double {
        switch state {
        case .completed: return 1.0
        case .running: return downloader?.totalProgress ?? 0
        case .queued, .failed, .cancelled: return 0
        }
    }
}

// MARK: - Download Queue Manager

/// ダウンロードキュー全体を管理するマネージャー
/// シートや画面を閉じてもダウンロードが継続する（アプリ内バックグラウンド実行）
@MainActor
@Observable
final class DownloadQueueManager {
    static let shared = DownloadQueueManager()

    // MARK: - Properties

    /// 全タスク（現在のバッチ）
    private(set) var tasks: [DownloadQueueTask] = []

    /// 同時ダウンロード数
    private let maxConcurrentDownloads = 2

    private var driveService: DriveService?
    private var authorizer: (any GTMSessionFetcherAuthorizer)?
    private var accessToken: String?

    /// 各タスク開始前にアクセストークンを最新化するためのクロージャ
    /// バックグラウンドダウンロードは長時間実行されうるため、configure時の
    /// トークンをキャッシュしたまま使い続けると途中で失効する可能性がある
    private var refreshAccessToken: (() async -> String?)?

    /// アプリがバックグラウンドに移行しても処理を継続するためのタスクID
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// タスク終了時のコールバック（ライブラリのキャッシュ更新用）
    var onTaskFinished: ((DownloadQueueTask) -> Void)?

    /// キューが空になったときのコールバック（完了件数, 失敗件数）
    var onQueueDrained: ((_ completed: Int, _ failed: Int) -> Void)?

    /// シリーズサムネイルが（ディスクへの書き込みまで完了して）更新されたときのコールバック
    /// `onTaskFinished`はタスク完了と同時に同期的に発火するため、それより後に非同期で
    /// 完了するサムネイル生成の通知には使えない。ここで生成完了を正確なタイミングで通知する
    var onSeriesThumbnailUpdated: ((_ folderId: String) -> Void)?

    // MARK: - Computed Properties

    /// 未終了（待機中・実行中）のタスク
    var pendingTasks: [DownloadQueueTask] { tasks.filter { !$0.state.isFinished } }

    /// キューが動作中かどうか
    var isActive: Bool { !pendingTasks.isEmpty }

    /// 終了済みタスク数
    var finishedCount: Int { tasks.filter { $0.state.isFinished }.count }

    /// 全タスク数
    var totalCount: Int { tasks.count }

    /// 実行中タスクの平均進捗を含めた全体進捗（0.0〜1.0）
    var overallProgress: Double {
        guard !tasks.isEmpty else { return 0 }
        let sum = tasks.reduce(0.0) { $0 + $1.progress }
        return sum / Double(tasks.count)
    }

    private init() {}

    // MARK: - Configuration

    /// 認証情報とDriveServiceを設定
    func configure(
        driveService: DriveService,
        authorizer: (any GTMSessionFetcherAuthorizer)?,
        accessToken: String?,
        refreshAccessToken: (() async -> String?)? = nil
    ) {
        self.driveService = driveService
        self.authorizer = authorizer
        self.accessToken = accessToken
        self.refreshAccessToken = refreshAccessToken
    }

    // MARK: - Enqueue

    /// ターゲットをキューに追加
    /// - Returns: 追加された（または既存の）タスク。既にダウンロード済みの場合はnil
    @discardableResult
    func enqueue(_ target: DownloadTarget) -> DownloadQueueTask? {
        let driveFileId: String
        switch target {
        case .file(let item): driveFileId = item.id
        case .folder(let id, _): driveFileId = id
        }

        if isDownloaded(driveFileId: driveFileId) {
            return nil
        }

        // 既にキューにある場合はそのタスクを返す
        if let existingTask = tasks.first(where: { $0.driveFileId == driveFileId && !$0.state.isFinished }) {
            return existingTask
        }

        clearFinishedIfIdle()

        // 同じファイルの失敗/キャンセル済みタスクが残っていれば、再試行時に重複させず置き換える
        tasks.removeAll { $0.driveFileId == driveFileId && $0.state.isFinished }

        let task = DownloadQueueTask(target: target)
        tasks.append(task)
        beginBackgroundTaskIfNeeded()
        processQueue()
        return task
    }

    /// 複数のアーカイブをまとめてキューに追加（ダウンロード済み・重複はスキップ）
    /// - Returns: 新規に追加した件数
    @discardableResult
    func enqueue(items: [DriveItem]) -> Int {
        clearFinishedIfIdle()

        var added = 0
        for item in items where item.isArchive {
            if isDownloaded(driveFileId: item.id) { continue }
            if tasks.contains(where: { $0.driveFileId == item.id && !$0.state.isFinished }) { continue }

            // 同じファイルの失敗/キャンセル済みタスクが残っていれば、再試行時に重複させず置き換える
            tasks.removeAll { $0.driveFileId == item.id && $0.state.isFinished }

            tasks.append(DownloadQueueTask(target: .file(item)))
            added += 1
        }

        if added > 0 {
            beginBackgroundTaskIfNeeded()
            processQueue()
        }
        return added
    }

    /// フォルダ内の全アーカイブをキューに追加（シリーズ一括ダウンロード）
    /// - Returns: 新規に追加した件数
    func enqueueSeries(folder: DriveItem) async throws -> Int {
        let archives = try await fetchAllArchives(inFolder: folder.id)
        return enqueue(items: archives)
    }

    /// フォルダ内の全アーカイブをリモートから再取得し、指定アイテム以降をキューに追加
    /// UI側の表示リストはページング・検索フィルタで一部しか見えていない場合があるため、
    /// 対象を必ず全件取得してから判定する（`enqueueSeries`と同じ方針）
    /// - Returns: (新規に追加した件数, 対象巻数（ダウンロード済み含む全件）)
    func enqueueFrom(folderId: String, item: DriveItem) async throws -> (added: Int, total: Int) {
        let archives = try await fetchAllArchives(inFolder: folderId)
        guard let index = archives.firstIndex(where: { $0.id == item.id }) else {
            return (0, 0)
        }
        let volumes = Array(archives[index...])
        let added = enqueue(items: volumes)
        return (added, volumes.count)
    }

    /// フォルダ内の全アーカイブをページングしながら取得し、名前順にソートして返す
    private func fetchAllArchives(inFolder folderId: String) async throws -> [DriveItem] {
        guard let driveService else { return [] }
        return try await driveService.fetchArchivesNaturalSorted(inFolder: folderId)
    }

    // MARK: - Cancel / Clear

    /// タスクをキャンセル
    func cancel(_ task: DownloadQueueTask) {
        guard !task.state.isFinished else { return }
        task.cancelRequested = true

        switch task.state {
        case .queued:
            task.state = .cancelled
            taskDidFinish(task)
        case .running:
            task.downloader?.cancel()
            task.runner?.cancel()
        case .completed, .failed, .cancelled:
            break
        }
    }

    /// 全ての未終了タスクをキャンセル
    func cancelAll() {
        for task in pendingTasks {
            cancel(task)
        }
    }

    /// 終了済みタスクを一覧から削除
    func clearFinished() {
        tasks.removeAll { $0.state.isFinished }
    }

    // MARK: - Query

    /// 指定したDriveファイルIDが待機中・実行中かどうか
    func isInQueue(driveFileId: String) -> Bool {
        tasks.contains { $0.driveFileId == driveFileId && !$0.state.isFinished }
    }

    /// 指定したDriveファイルIDの未終了タスクを取得
    func task(forDriveFileId id: String) -> DownloadQueueTask? {
        tasks.first { $0.driveFileId == id && !$0.state.isFinished }
    }

    /// 指定したDriveファイルIDの最新タスクを取得（終了済みも含む）
    /// シート再表示時に、失敗/キャンセル済みの状態を復元するために使用する
    func lastKnownTask(forDriveFileId id: String) -> DownloadQueueTask? {
        tasks.last { $0.driveFileId == id }
    }

    /// 指定フォルダ内に未終了タスクがあるかどうか
    func hasPendingTasks(inFolder folderId: String) -> Bool {
        tasks.contains { !$0.state.isFinished && ($0.parentFolderId == folderId || $0.driveFileId == folderId) }
    }

    // MARK: - Private

    /// キューが完全に停止していれば、前バッチの終了済みタスクをクリア
    private func clearFinishedIfIdle() {
        if pendingTasks.isEmpty {
            tasks.removeAll { $0.state.isFinished }
        }
    }

    private func isDownloaded(driveFileId: String) -> Bool {
        if let existing = try? LocalStorageService.shared.findComic(byDriveFileId: driveFileId),
           existing.status == .completed {
            return true
        }
        return false
    }

    /// 空きスロットがあれば待機中タスクを開始
    private func processQueue() {
        let runningCount = tasks.filter { $0.state == .running }.count
        guard runningCount < maxConcurrentDownloads else { return }

        let slots = maxConcurrentDownloads - runningCount
        for task in tasks.filter({ $0.state == .queued }).prefix(slots) {
            start(task)
        }
    }

    private func start(_ task: DownloadQueueTask) {
        guard let driveService else {
            task.state = .failed("認証情報が設定されていません")
            taskDidFinish(task)
            return
        }

        task.state = .running
        let downloader = DownloaderViewModel(driveService: driveService)
        task.downloader = downloader

        task.runner = Task { [weak self] in
            // 実行開始直前にトークンを最新化してから設定する（長時間キュー待機後の失効対策）
            let freshToken = await self?.refreshAccessToken?() ?? self?.accessToken
            downloader.configure(with: self?.authorizer, accessToken: freshToken)

            let comic: LocalComic?
            switch task.target {
            case .file(let item):
                comic = await downloader.downloadAndExtract(item: item)
            case .folder(let id, let name):
                comic = await downloader.downloadFolder(folderId: id, folderName: name)
            }

            if task.cancelRequested {
                task.state = .cancelled
            } else if let comic {
                task.comic = comic
                task.state = .completed
            } else {
                task.state = .failed(downloader.errorMessage ?? "ダウンロードに失敗しました")
            }
            task.runner = nil
            self?.taskDidFinish(task)
        }
    }

    private func taskDidFinish(_ task: DownloadQueueTask) {
        onTaskFinished?(task)

        if case .completed = task.state, let comic = task.comic {
            Task { await maybeGenerateSeriesThumbnail(for: task, comic: comic) }
        }

        if pendingTasks.isEmpty {
            let completed = tasks.filter { $0.state == .completed }.count
            let failed = tasks.filter {
                if case .failed = $0.state { return true }
                return false
            }.count
            endBackgroundTaskIfNeeded()
            onQueueDrained?(completed, failed)
        } else {
            processQueue()
        }
    }

    /// ダウンロード完了したファイルがシリーズの1巻であれば、永続サムネイルを生成する
    /// 既にキャッシュがある場合は何もしない（1巻が入れ替わるケースは非対応、全データ削除で再生成される）
    private func maybeGenerateSeriesThumbnail(for task: DownloadQueueTask, comic: LocalComic) async {
        guard case .file(let item) = task.target, let folderId = item.parentId else { return }
        guard let firstImage = comic.imagePaths.first else { return }
        guard SeriesThumbnailStore.shared.cachedThumbnailURL(forFolderId: folderId) == nil else { return }

        guard let siblings = try? await driveService?.fetchArchivesNaturalSorted(inFolder: folderId),
              siblings.first?.id == item.id else { return }

        if await SeriesThumbnailStore.shared.generateThumbnail(forFolderId: folderId, imageURL: firstImage) != nil {
            onSeriesThumbnailUpdated?(folderId)
        }
    }

    // MARK: - Background Task

    /// アプリがバックグラウンドに移行しても猶予時間内は処理を継続する
    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "DownloadQueue") { [weak self] in
            // 猶予時間切れ: 残っている未終了タスクをキャンセルし、スロットを解放してからバックグラウンドタスクを終了する
            // （キャンセルしないと.runningのまま残り続け、フォアグラウンド復帰後もキューが進まなくなる）
            Task { @MainActor in
                self?.cancelAll()
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
