// ComicSource.swift
// GD-MangaReader
//
// 漫画データソース（ローカルまたはリモート）の抽象化
//

import Foundation
import UIKit
import SwiftUI
import ImageIO

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
    /// 指定ページが「見開き画像（横長）」かどうか
    func isWidePage(at index: Int) async -> Bool
}

// MARK: - Image Utilities

extension UIImage {
    /// 指定されたサイズに画像をダウンサンプリングする
    func downsampled(to targetSize: CGSize) -> UIImage {
        let scale = min(targetSize.width / self.size.width, targetSize.height / self.size.height)
        if scale >= 1.0 { return self }
        
        let newSize = CGSize(
            width: self.size.width * scale,
            height: self.size.height * scale
        )
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Local Comic Source

/// ローカルにダウンロード済みの漫画ソース
struct LocalComicSource: ComicSource {
    private let comic: LocalComic
    
    // 表示用ターゲットサイズ（UI側から注入されるべきだが、簡易的にハードコードを避けるためのフォールバック）
    // 理想は ReaderView から渡すことですが、非同期画像取得時のオーバーヘッドを減らすため
    // 現状は iOS の標準的な最大画面サイズ（iPad等）を想定した固定値を使用します。
    private let maxDisplaySize = CGSize(width: 2732, height: 2048) 
    
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
        let targetSize = self.maxDisplaySize
        
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data) else {
                return nil
            }
            return uiImage.downsampled(to: targetSize)
        }.value
    }
    
    func isWidePage(at index: Int) async -> Bool {
        guard index >= 0 && index < comic.imagePaths.count else { return false }
        let url = comic.imagePaths[index]
        
        return await Task.detached(priority: .userInitiated) {
            // 画像のサイズ情報のみを取得（メモリ節約のため）
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
                return false
            }
            // 横幅が高さの1.2倍以上あれば見開きとみなす
            return width > height * 1.2
        }.value
    }
    
    func saveProgress(page: Int) async {
        var updatedComic = comic
        updatedComic.lastReadPage = page
        updatedComic.lastReadAt = Date()
        try? LocalStorageService.shared.updateComic(updatedComic)
    }
}

// MARK: - Remote Comic Source

/// Google Drive上のフォルダを直接読むリモートソース
final class RemoteComicSource: ComicSource {
    let id: String
    let title: String
    let pageCount: Int
    let parentId: String?
    var lastReadPage: Int = 0
    
    private let files: [DriveItem]
    let driveService: DriveService
    // 画像キャッシュ (Index -> UIImage)
    private var imageCache: [Int: UIImage] = [:]
    // ワイドページ情報のキャッシュ
    private var widePageCache: [Int: Bool] = [:]
    private let maxDisplaySize = CGSize(width: 2732, height: 2048)
    
    init(folderId: String, title: String, files: [DriveItem], driveService: DriveService, parentId: String? = nil) {
        self.id = folderId
        self.title = title
        self.files = files
        self.pageCount = files.count
        self.driveService = driveService
        self.parentId = parentId
    }
    
    func image(at index: Int) async throws -> UIImage? {
        return try await fetchImage(at: index)
    }
    
    @MainActor
    private func fetchImage(at index: Int) async throws -> UIImage? {
        guard index >= 0 && index < files.count else { return nil }
        
        if let cached = imageCache[index] {
            return cached
        }
        
        let file = files[index]
        
        // DriveService から取得
        guard let data = try? await driveService.downloadFileData(fileId: file.id) else {
            return nil
        }
        
        guard let uiImage = UIImage(data: data) else { return nil }
        let targetSize = self.maxDisplaySize
        
        // ダウンサンプリング
        let processedImage = await Task.detached(priority: .userInitiated) {
            return uiImage.downsampled(to: targetSize)
        }.value
        
        if imageCache.count > 20 {
            imageCache.removeAll()
        }
        imageCache[index] = processedImage
        
        return processedImage
    }
    
    func saveProgress(page: Int) async {
        self.lastReadPage = page
    }
    
    @MainActor
    func isWidePage(at index: Int) async -> Bool {
        guard index >= 0 && index < files.count else { return false }
        
        if let cached = widePageCache[index] {
            return cached
        }
        
        do {
            let file = files[index]
            let data = try await driveService.downloadFileData(fileId: file.id)
            
            let isWide = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                      let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
                    return false
                }
                return width > height * 1.2
            }.value
            
            widePageCache[index] = isWide
            return isWide
        } catch {
            return false
        }
    }
}
