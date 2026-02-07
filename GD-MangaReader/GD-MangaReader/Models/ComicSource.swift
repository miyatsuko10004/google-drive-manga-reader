// ComicSource.swift
// GD-MangaReader
//
// 漫画データソース（ローカルまたはリモート）の抽象化
//

import Foundation
import UIKit
import SwiftUI

/// 漫画のページデータを提供するプロトコル
protocol ComicSource {
    /// ID
    var id: String { get }
    /// タイトル
    var title: String { get }
    /// 総ページ数
    var pageCount: Int { get }
    /// 指定ページの画像を取得（非同期）
    func image(at index: Int) async throws -> UIImage?
    /// 読書進捗の保存
    func saveProgress(page: Int) async
    /// 最後に読んだページ
    var lastReadPage: Int { get }
}

// MARK: - Local Comic Source

/// ローカルにダウンロード済みの漫画ソース
struct LocalComicSource: ComicSource {
    private let comic: LocalComic
    
    init(comic: LocalComic) {
        self.comic = comic
    }
    
    var id: String { comic.id }
    var title: String { comic.title }
    var pageCount: Int { comic.pageCount }
    var lastReadPage: Int { comic.lastReadPage }
    
    func image(at index: Int) async throws -> UIImage? {
        guard index >= 0 && index < comic.imagePaths.count else { return nil }
        let url = comic.imagePaths[index]
        
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data) else {
                return nil
            }
            // 画面サイズに合わせてダウンサンプリング
            return downsample(image: uiImage, to: UIScreen.main.bounds.size)
        }.value
    }
    
    func saveProgress(page: Int) async {
        var updatedComic = comic
        updatedComic.lastReadPage = page
        updatedComic.lastReadAt = Date()
        try? await LocalStorageService.shared.updateComic(updatedComic)
    }
    
    /// 画像をダウンサンプリング（メモリ効率化）
    private func downsample(image: UIImage, to targetSize: CGSize) -> UIImage {
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        if scale >= 1.0 { return image }
        
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Remote Comic Source

// MARK: - Remote Comic Source

/// Google Drive上のフォルダを直接読むリモートソース
final class RemoteComicSource: ComicSource {
    let id: String
    let title: String
    let pageCount: Int
    var lastReadPage: Int = 0
    
    private let files: [DriveItem]
    private let driveService: DriveService
    // 画像キャッシュ (Index -> UIImage)
    private var imageCache: [Int: UIImage] = [:]
    
    init(folderId: String, title: String, files: [DriveItem], driveService: DriveService) {
        self.id = folderId
        self.title = title
        self.files = files
        self.pageCount = files.count
        self.driveService = driveService
    }
    
    func image(at index: Int) async throws -> UIImage? {
        // キャッシュにあれば返す（MainActor前提ならロック不要だが、念のためロックするか、あるいはMainActorにするか）
        // ここでは簡易的にActorなしで実装するが、UIからの呼び出しはMainActorで行われる想定
        // データ競合を避けるため @MainActor をつけるのが安全
        return try await fetchImage(at: index)
    }
    
    @MainActor
    private func fetchImage(at index: Int) async throws -> UIImage? {
        guard index >= 0 && index < files.count else { return nil }
        
        if let cached = imageCache[index] {
            return cached
        }
        
        let file = files[index]
        print("📥 [Remote] Fetching image: \(file.name) (\(index))")
        
        // DriveService (MainActor) から取得
        guard let data = try? await driveService.downloadFileData(fileId: file.id) else {
            return nil
        }
        
        guard let uiImage = UIImage(data: data) else { return nil }
        
        // ダウンサンプリング（重い処理はDetached Taskで）
        let processedImage = await Task.detached(priority: .userInitiated) {
            return Self.downsample(image: uiImage, to: UIScreen.main.bounds.size)
        }.value
        
        // キャッシュ制御
        if imageCache.count > 20 {
            imageCache.removeAll()
        }
        imageCache[index] = processedImage
        
        return processedImage
    }
    
    func saveProgress(page: Int) async {
        self.lastReadPage = page
    }
    
    private static func downsample(image: UIImage, to targetSize: CGSize) -> UIImage {
        let sc = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        if sc >= 1.0 { return image }
        let newSize = CGSize(width: image.size.width * sc, height: image.size.height * sc)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
