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
    
    private let driveService: DriveService
    
    // MARK: - Initialization
    
    init(driveService: DriveService? = nil) {
        self.driveService = driveService ?? DriveService()
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
            let result = try await driveService.listFiles(
                in: currentFolderId,
                pageToken: nil
            )
            items = result.items
            nextPageToken = result.nextPageToken
        } catch {
            errorMessage = error.localizedDescription
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
        currentFolderId = folderPath.last?.id
        items = []
        await loadFiles()
    }
    
    /// ルートに戻る
    func navigateToRoot() async {
        folderPath = []
        currentFolderId = nil
        items = []
        await loadFiles()
    }
    
    /// リフレッシュ
    func refresh() async {
        await loadFiles()
    }
}

// MARK: - Import for GTMFetcherAuthorizationProtocol
import GoogleAPIClientForREST_Drive
