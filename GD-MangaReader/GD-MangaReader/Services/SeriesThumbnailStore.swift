// SeriesThumbnailStore.swift
// GD-MangaReader
//
// シリーズ（Driveフォルダ）ごとの永続サムネイルキャッシュ管理サービス

import Foundation
import ImageIO
import UIKit

/// シリーズ（Driveフォルダid）ごとに1巻の表紙サムネイルを永続保存するサービス
/// シリーズ単位のディレクトリは存在しないため、Documents直下にフラットな専用ディレクトリを持ち、
/// ファイル名にDriveフォルダidを使うことでシリーズと1:1対応させる
final class SeriesThumbnailStore: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = SeriesThumbnailStore()

    // MARK: - Properties

    /// Documentsディレクトリ
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// シリーズサムネイル保存ディレクトリ
    var directory: URL {
        documentsDirectory.appendingPathComponent(Config.Storage.seriesThumbnailsDirectoryName)
    }

    private let fileManager = FileManager.default

    /// ディレクトリ操作のスレッドセーフなアクセスのための再帰的ロック
    /// (ストレージ全削除がバックグラウンドスレッドから、サムネイル生成がMainActorから
    /// それぞれ非同期に走るため、`LocalStorageService`と同様の保護が必要)
    private let lock = NSRecursiveLock()

    // MARK: - Initialization

    private init() {
        lock.lock()
        defer { lock.unlock() }
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public Methods

    /// 指定フォルダの既存キャッシュファイルURL（存在すれば）
    func cachedThumbnailURL(forFolderId folderId: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(forFolderId: folderId)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// ローカル画像（1巻のページ1）から縮小JPEGを生成して保存する
    /// 横長画像（見開きスキャン等）の場合は、左上を起点に1ページ分（左半分）を切り出して保存する
    /// デコード・ダウンサンプル・エンコードはメインスレッドを塞がないようオフロードする
    @discardableResult
    func generateThumbnail(forFolderId folderId: String, imageURL: URL) async -> URL? {
        let jpegData: Data? = await Task.detached(priority: .utility) {
            let targetSize = Config.Storage.seriesThumbnailTargetSize
            let isWide = Self.isWideImage(at: imageURL)

            // 横長の場合は切り出し後も目標解像度を保てるよう2倍サイズでデコードする
            let decodeSize = isWide
                ? CGSize(width: targetSize.width * 2, height: targetSize.height * 2)
                : targetSize

            guard var image = UIImage.downsampledImage(from: imageURL, to: decodeSize) else {
                return nil
            }

            if isWide, let cropped = Self.cropLeadingPage(of: image) {
                image = cropped
            }

            return image.jpegData(compressionQuality: 0.8)
        }.value

        guard let jpegData else { return nil }

        return saveThumbnail(jpegData: jpegData, folderId: folderId)
    }

    private func saveThumbnail(jpegData: Data, folderId: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        // removeAll()等でディレクトリが削除されている可能性があるため、書き込み前に再作成する
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let destination = fileURL(forFolderId: folderId)
        do {
            try jpegData.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    /// 指定フォルダのキャッシュを削除
    func removeThumbnail(forFolderId folderId: String) {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL(forFolderId: folderId))
    }

    /// 全キャッシュを削除
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// キャッシュディレクトリ全体の使用サイズ
    func calculateStorageUsage() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    // MARK: - Helpers

    private func fileURL(forFolderId folderId: String) -> URL {
        directory.appendingPathComponent("\(folderId).jpg")
    }

    /// 画像が横長（見開き）かどうかをピクセル寸法だけで判定する（フルデコードはしない）
    /// 閾値は`ComicSource`のisWidePageと同じ「幅 > 高さ × 1.2」
    /// kCGImagePropertyPixelWidth/Heightは回転適用前の値のため、EXIF orientationが
    /// 90度回転系（5〜8）の場合は幅と高さを入れ替えて表示上の寸法で判定する
    /// （切り出しは回転適用後の画像に対して行うため、判定もそれに合わせる必要がある）
    private static func isWideImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return false
        }

        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let isRotated90 = (5...8).contains(orientation)
        let displayWidth = isRotated90 ? height : width
        let displayHeight = isRotated90 ? width : height

        return displayWidth > displayHeight * 1.2
    }

    /// 見開き画像から左上を起点に1ページ分（左半分）を切り出す
    static func cropLeadingPage(of image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let rect = CGRect(x: 0, y: 0, width: cgImage.width / 2, height: cgImage.height)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
