// StorageViewModel.swift
// GD-MangaReader
//
// ストレージ使用状況管理ViewModel

import Foundation
import SwiftUI

@MainActor
@Observable
final class StorageViewModel {
    // MARK: - Properties
    
    /// 保存済みコミックリスト（サイズ情報付き）
    private(set) var comics: [ComicStorageItem] = []
    
    /// 総使用容量
    private(set) var totalUsage: Int64 = 0
    
    /// 読み込み中かどうか
    private(set) var isLoading: Bool = false
    
    /// エラーメッセージ
    private(set) var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let storageService = LocalStorageService.shared
    
    // MARK: - Types
    
    struct ComicStorageItem: Identifiable, Sendable {
        let id: String
        let title: String
        let size: Int64
        let localComic: LocalComic
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
    
    var formattedTotalUsage: String {
        ByteCountFormatter.string(fromByteCount: totalUsage, countStyle: .file)
    }
    
    // MARK: - Methods
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        let service = storageService
        
        do {
            // 重い処理なのでバックグラウンドで実行
            let (items, total) = try await Task.detached(priority: .userInitiated) {
                let localComics = try service.loadComics()
                var items: [ComicStorageItem] = []
                var total: Int64 = 0
                
                for comic in localComics {
                    let size = service.calculateSize(of: comic)
                    items.append(ComicStorageItem(
                        id: comic.id,
                        title: comic.title,
                        size: size,
                        localComic: comic
                    ))
                    total += size
                }
                
                // サイズ順にソート
                let sortedItems = items.sorted { $0.size > $1.size }
                return (sortedItems, total)
            }.value
            
            self.comics = items
            self.totalUsage = total
            self.errorMessage = nil
            
        } catch {
            errorMessage = "データの読み込みに失敗しました: \(error.localizedDescription)"
        }
    }
    
    func deleteComic(_ item: ComicStorageItem) async {
        do {
            try await Task.detached {
                try LocalStorageService.shared.deleteComic(item.localComic)
            }.value
            await loadData()
        } catch {
            errorMessage = "削除に失敗しました: \(error.localizedDescription)"
        }
    }
    
    func deleteAll() async {
        do {
            try await Task.detached {
                try LocalStorageService.shared.clearAllComics()
            }.value
            await loadData()
        } catch {
            errorMessage = "全削除に失敗しました: \(error.localizedDescription)"
        }
    }
    
    func deleteCompletedComics() async {
        do {
            let completedItems = comics.filter { $0.localComic.readingProgress >= 1.0 }
            try await Task.detached {
                for item in completedItems {
                    try LocalStorageService.shared.deleteComic(item.localComic)
                }
            }.value
            await loadData()
        } catch {
            errorMessage = "読了済みデータの削除に失敗しました: \(error.localizedDescription)"
        }
    }
}
