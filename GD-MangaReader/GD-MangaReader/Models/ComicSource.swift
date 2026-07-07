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
    /// 指定されたデータから効率的にダウンサンプリングされたUIImageを作成する
    static func downsampledImage(from data: Data, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }
        
        return createThumbnail(from: imageSource, targetSize: targetSize)
    }
    
    /// 指定されたURLから効率的にダウンサンプリングされたUIImageを作成する
    static func downsampledImage(from url: URL, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
            return nil
        }
        
        return createThumbnail(from: imageSource, targetSize: targetSize)
    }
    
    private static func createThumbnail(from imageSource: CGImageSource, targetSize: CGSize) -> UIImage? {
        let maxDimension = max(targetSize.width, targetSize.height)
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        return UIImage(cgImage: downsampledImage)
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
            return UIImage.downsampledImage(from: url, to: targetSize)
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
        
        let targetSize = self.maxDisplaySize
        
        // ダウンサンプリング (Dataから直接生成)
        let processedImage = await Task.detached(priority: .userInitiated) {
            return UIImage.downsampledImage(from: data, to: targetSize)
        }.value
        
        // キャッシュ管理：現在のページから±10ページ以上離れているものを削除
        if imageCache.count > 20 {
            let keysToRemove = imageCache.keys.filter { abs($0 - index) > 10 }
            for key in keysToRemove {
                imageCache.removeValue(forKey: key)
            }
            // まだ多い場合は一番離れているものから消す（簡易LRU）
            if imageCache.count > 30 {
                if let farthestKey = imageCache.keys.max(by: { abs($0 - index) < abs($1 - index) }) {
                    imageCache.removeValue(forKey: farthestKey)
                }
            }
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
        
        let file = files[index]
        
        // 1. まずDriveItemに寸法が含まれているかチェック
        if let w = file.width, let h = file.height {
            let isWide = CGFloat(w) > CGFloat(h) * 1.2
            widePageCache[index] = isWide
            return isWide
        }
        
        // 2. 寸法がなければ（フォールバック）ダウンロードして判定
        do {
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
