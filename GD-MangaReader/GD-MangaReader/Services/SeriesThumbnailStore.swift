// SeriesThumbnailStore.swift
// GD-MangaReader
//
// シリーズ（Driveフォルダ）ごとの永続サムネイルキャッシュ管理サービス

import Foundation
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
    /// デコード・ダウンサンプル・エンコードはメインスレッドを塞がないようオフロードする
    @discardableResult
    func generateThumbnail(forFolderId folderId: String, imageURL: URL) async -> URL? {
        let jpegData: Data? = await Task.detached(priority: .utility) {
            guard let downsampled = UIImage.downsampledImage(
                from: imageURL,
                to: Config.Storage.seriesThumbnailTargetSize
            ) else {
                return nil
            }
            return downsampled.jpegData(compressionQuality: 0.8)
        }.value

        guard let jpegData else { return nil }

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
}
