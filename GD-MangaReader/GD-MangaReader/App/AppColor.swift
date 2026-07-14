// AppColor.swift
// GD-MangaReader
//
// デザイントークン（色のみ・最小構成）
// Assets.xcassets のカラーセットをセマンティックな名前で公開する。
// アクセントカラーは Assets.xcassets/AccentColor が自動適用されるため、
// `Color.accentColor` / `.tint` をそのまま使うこと。

import SwiftUI

extension Color {
    /// 成功状態（ダウンロード完了表示など）
    static let appSuccess = Color("AppSuccess")

    /// 警告・注意（オフラインモード、アーカイブアイコンなど）
    static let appWarning = Color("AppWarning")

    /// 破壊的操作・エラー（削除、失敗表示など）
    static let appDestructive = Color("AppDestructive")

    /// ダウンロード済みバッジ（サムネイル右上のチェックマーク）
    /// 白円の上に乗るためライト/ダーク共通の単一値
    static let appDownloadedBadge = Color("AppDownloadedBadge")

    /// プログレスバー・スピナーの共通ティント（ダウンロード進捗・解凍進捗・読了バー）
    /// アクセントカラーに統一（アセットの重複による値のズレを防ぐためエイリアスにする）
    static let appProgressTint = Color.accentColor
}
