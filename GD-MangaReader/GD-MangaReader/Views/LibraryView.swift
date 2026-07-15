// LibraryView.swift
// GD-MangaReader
//
// Google Drive内のファイルブラウザ画面

import SwiftUI
import UIKit
import Kingfisher

/// Driveファイルブラウザ画面
struct LibraryView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(StatusCenter.self) private var statusCenter
    @State private var libraryViewModel = LibraryViewModel()
    @State private var selectedItem: DriveItem?
    @State private var showingSignOutAlert = false
    @State private var readingSession: ComicSession?
    @State private var showingBulkDownloadConfirmation = false
    @State private var selectedFolderForBulk: DriveItem?
    @State private var showingCascadeDownloadConfirmation = false
    @State private var selectedItemForCascade: DriveItem?
    @State private var showingTrialDownloadConfirmation = false
    @State private var localRefreshTrigger = 0
    @State private var loadTask: Task<Void, Never>?

    private var downloadQueue: DownloadQueueManager { .shared }

    struct ComicSession: Identifiable, Equatable {
        var id: String { source.id }
        let source: any ComicSource
        
        static func == (lhs: ComicSession, rhs: ComicSession) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            mainContent
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            // 背景
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            contentLayer
            // ダウンロードキュープログレスバナーとトーストはルートの
            // .statusCenterOverlay()（StatusCenterOverlay.swift）が表示する
        }
        .navigationTitle(libraryViewModel.currentFolderName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            toolbarContent
        }
        .searchable(text: $libraryViewModel.searchText, prompt: "作品・フォルダを検索")
        .refreshable {
            await libraryViewModel.refresh()
        }
        .task {
            libraryViewModel.isOfflineMode = authViewModel.isOfflineMode
            libraryViewModel.configure(with: authViewModel.authorizer)
            downloadQueue.configure(
                driveService: libraryViewModel.driveService,
                authorizer: authViewModel.authorizer,
                accessToken: authViewModel.accessToken,
                refreshAccessToken: { await authViewModel.refreshedAccessToken() }
            )
            downloadQueue.onTaskFinished = { _ in
                libraryViewModel.refreshDownloadedComics()
            }
            downloadQueue.onSeriesThumbnailUpdated = { folderId in
                // 実際にディスクへのサムネイル生成が完了したタイミングで前段キャッシュを無効化し、
                // 次回表示時に新しいファイルを拾わせる
                libraryViewModel.invalidateSeriesThumbnail(folderId: folderId)
            }
            downloadQueue.onQueueDrained = { completed, failed in
                guard completed + failed > 0 else { return }
                // 非アクティブ時はDownloadQueueManagerが発行するローカル通知が担当するため、
                // トースト（＋ハプティクス）はフォアグラウンドでのみ表示する（二重フィードバック防止）
                guard UIApplication.shared.applicationState == .active else { return }
                if failed == 0 {
                    statusCenter.show(ToastData(
                        title: "ダウンロード完了",
                        message: "\(completed)件のダウンロードが完了しました",
                        type: .success
                    ))
                } else {
                    statusCenter.show(ToastData(
                        title: "ダウンロード完了 (\(failed)件失敗)",
                        message: "\(completed)件完了、\(failed)件失敗しました",
                        type: .error
                    ))
                }
            }
            await libraryViewModel.loadFiles()
        }
        .onChange(of: authViewModel.isOfflineMode) { _, newValue in
            loadTask?.cancel()
            libraryViewModel.isOfflineMode = newValue
            loadTask = Task {
                await libraryViewModel.loadFiles()
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            if newValue == nil {
                localRefreshTrigger += 1
            }
        }
        .onChange(of: readingSession) { _, newValue in
            if newValue == nil {
                libraryViewModel.refreshDownloadedComics()
            }
        }
        .modifier(AlertsAndSheetsModifier(
            showingSignOutAlert: $showingSignOutAlert,
            showingBulkDownloadConfirmation: $showingBulkDownloadConfirmation,
            selectedItem: $selectedItem,
            selectedFolderForBulk: $selectedFolderForBulk,
            showingCascadeDownloadConfirmation: $showingCascadeDownloadConfirmation,
            selectedItemForCascade: $selectedItemForCascade,
            showingTrialDownloadConfirmation: $showingTrialDownloadConfirmation,
            readingSession: $readingSession,
            authViewModel: authViewModel,
            libraryViewModel: libraryViewModel
        ))
    }
    
    @ViewBuilder
    private var contentLayer: some View {
        VStack(spacing: 0) {
            if authViewModel.isOfflineMode {
                offlineBannerView
            }

            if libraryViewModel.isLoading && libraryViewModel.items.isEmpty {
                shimmerLoadingView
            } else if let error = libraryViewModel.errorMessage {
                errorView(message: error)
            } else if libraryViewModel.items.isEmpty {
                emptyView
            } else {
                fileListContent
            }
        }
    }
    

    // MARK: - Subviews
    
    /// ファイル一覧コンテンツ
    /// ソート・表示モードのコントロールバーはpinnedViewsのセクションヘッダーとして配置する。
    /// これによりパンくずとアイテム一覧の間という自然な位置に置きつつ、長いリストを
    /// スクロール中でも画面上部に固定されて操作できる（safeAreaInsetだとおすすめシェルフや
    /// パンくずより上に来てしまうため、この方式を採用）
    @ViewBuilder
    private var fileListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                recommendationSection

                // パンくずリスト
                if !libraryViewModel.folderPath.isEmpty {
                    breadcrumbView
                }

                Section {
                    itemsSection

                    // さらに読み込み
                    if libraryViewModel.hasMoreItems {
                        autoLoadMoreView
                    }
                } header: {
                    listControlBar
                }
            }
            .padding()
        }
    }

    /// ソート・表示モードのコントロールバー
    private var listControlBar: some View {
        HStack {
            // ソート選択（現在のソート順をラベルに表示するMenu）
            Menu {
                Picker("並び替え", selection: $libraryViewModel.sortOption) {
                    ForEach(LibraryViewModel.SortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(libraryViewModel.sortOption.label)
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                .foregroundColor(.secondary)
                // タップ領域を確保する（見た目はcaptionのまま）
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                // VoiceOverでは1要素として「並び替え: 現在のソート順」と読み上げる
                .accessibilityElement(children: .combine)
                .accessibilityLabel("並び替え: \(libraryViewModel.sortOption.label)")
            }

            Spacer()

            // 表示モード切り替え（2状態のトグル。アイコンは「押すと切り替わる先」を示す）
            Button {
                withAnimation {
                    libraryViewModel.viewMode = (libraryViewModel.viewMode == .grid) ? .list : .grid
                }
            } label: {
                let nextMode: LibraryViewModel.ViewMode =
                    (libraryViewModel.viewMode == .grid) ? .list : .grid
                Image(systemName: nextMode.icon)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(
                libraryViewModel.viewMode == .grid ? "リスト表示に切り替え" : "グリッド表示に切り替え"
            )
        }
        .frame(height: 36)
        // ピン留め時に下をスクロールするセルを隠すため、画面背景と同じ色を敷く
        .background(Color(.systemGroupedBackground))
    }
    
    /// おすすめセクション
    @ViewBuilder
    private var recommendationSection: some View {
        if libraryViewModel.folderPath.isEmpty {
            if !libraryViewModel.nextRecommendedComics.isEmpty {
                RecentComicsShelfView(
                    title: "続きを読みませんか？",
                    readingSession: $readingSession,
                    recentComics: libraryViewModel.nextRecommendedComics
                )
                .padding(.bottom, 8)
            }
            
            if !libraryViewModel.recentComics.isEmpty {
                RecentComicsShelfView(
                    title: "最近読んだ作品",
                    readingSession: $readingSession,
                    recentComics: libraryViewModel.recentComics
                )
                Divider().padding(.vertical, 8)
            }
        }
    }
    
    /// アイテム一覧セクション
    @ViewBuilder
    private var itemsSection: some View {
        switch libraryViewModel.viewMode {
        case .grid:
            DriveItemGridView(
                gridColumns: gridColumns,
                libraryViewModel: libraryViewModel,
                onItemTap: handleItemTap,
                onBulkDownload: handleBulkDownload,
                onDownloadSingle: handleDownloadSingle,
                onDownloadFrom: handleDownloadFrom
            )
        case .list:
            DriveItemListView(
                libraryViewModel: libraryViewModel,
                onItemTap: handleItemTap,
                onBulkDownload: handleBulkDownload,
                onDownloadSingle: handleDownloadSingle,
                onDownloadFrom: handleDownloadFrom
            )
        }
    }
    
    
    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    Task { await libraryViewModel.navigateToRoot() }
                } label: {
                    Label("マイドライブ", systemImage: "house")
                        .font(.caption)
                }
                
                ForEach(libraryViewModel.folderPath) { folder in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button(folder.name) {
                        Task {
                            await libraryViewModel.navigateToIntermediateFolder(folder)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    /// さらに読み込みトリガー
    private var autoLoadMoreView: some View {
        Color.clear
            .frame(height: 20)
            .onAppear {
                if libraryViewModel.hasMoreItems && !libraryViewModel.isLoading {
                    Task { await libraryViewModel.loadMoreFiles() }
                }
            }
    }
    
    /// オフラインモードバナー（オフライン時のみ表示）
    /// 「オンラインに戻す」ボタンで、どの画面階層からでもワンタップで復帰できる
    private var offlineBannerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("オフラインモード")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("ダウンロード済みのみ表示")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            Button {
                withAnimation {
                    authViewModel.isOfflineMode = false
                }
            } label: {
                Text("オンラインに戻す")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.25)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.appWarning)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    /// スケルトンUI（Shimmer）
    private var shimmerLoadingView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .aspectRatio(1, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(height: 14)
                            .padding(.horizontal, 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 50, height: 10)
                    }
                    .padding(8)
                    .shimmer()
                }
            }
            .padding()
        }
    }
    
    /// 空の状態表示
    private var emptyView: some View {
        ContentUnavailableView(
            "ファイルがありません",
            systemImage: "folder.badge.questionmark",
            description: Text("このフォルダには対応ファイルがありません\n(ZIP, RAR, CBZ, CBR)")
        )
    }
    
    /// エラー表示
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "エラーが発生しました",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            
            Button("再試行") {
                Task { await libraryViewModel.loadFiles() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    /// ツールバー
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !libraryViewModel.folderPath.isEmpty {
                Button {
                    Task { await libraryViewModel.navigateBack() }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                // オフラインモード切り替え
                // （常設のトグル行は廃止し、メニュー内トグル＋オフライン時のバナーに集約）
                Toggle(isOn: Binding(
                    get: { authViewModel.isOfflineMode },
                    set: { newValue in
                        withAnimation {
                            authViewModel.isOfflineMode = newValue
                        }
                    }
                )) {
                    Label("オフラインモード", systemImage: "wifi.slash")
                }

                Divider()

                // ユーザー情報
                Section {
                    Text(authViewModel.userName)
                    Text(authViewModel.userEmail)
                        .font(.caption)
                }
                
                Divider()

                // 試し読み（ルート表示時のみ）
                if libraryViewModel.folderPath.isEmpty {
                    Button {
                        handleTrialDownload()
                    } label: {
                        Label("試し読み（全シリーズの1巻）", systemImage: "sparkles")
                    }
                }

                // ダウンロード一覧（シートはルートの.statusCenterOverlay()が表示する）
                Button {
                    statusCenter.showDownloadQueue()
                } label: {
                    Label("ダウンロード", systemImage: "arrow.down.circle")
                }

                // ストレージ管理
                NavigationLink {
                    StorageManagementView()
                } label: {
                    Label("ストレージ管理", systemImage: "externaldrive")
                }
                
                Divider()
                
                // サインアウト
                Button(role: .destructive) {
                    showingSignOutAlert = true
                } label: {
                    Label("サインアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    
    // MARK: - Actions

    /// オフラインモード時にダウンロード操作をブロックし、案内トーストを表示
    private func blockIfOffline() -> Bool {
        guard authViewModel.isOfflineMode else { return false }
        statusCenter.show(ToastData(
            title: "オフラインモード",
            message: "オフライン中はダウンロードできません。",
            type: .error
        ))
        return true
    }

    /// フォルダ長押し: シリーズ一括ダウンロードの確認
    private func handleBulkDownload(_ folder: DriveItem) {
        guard !blockIfOffline() else { return }
        selectedFolderForBulk = folder
        showingBulkDownloadConfirmation = true
    }

    /// 巻の長押し: この巻のみダウンロード（即キュー追加）
    private func handleDownloadSingle(_ item: DriveItem) {
        guard !blockIfOffline() else { return }
        // 既にキュー中の場合はenqueueが既存タスクを返すため、事前にチェックして
        // 「追加しました」という誤解を招くトーストが出ないようにする
        let alreadyQueued = downloadQueue.isInQueue(driveFileId: item.id)
        if downloadQueue.enqueue(.file(item)) != nil && !alreadyQueued {
            statusCenter.show(ToastData(
                title: "ダウンロード開始",
                message: "\(item.name) をキューに追加しました",
                type: .info
            ))
        }
    }

    /// 巻の長押し: この巻以降をダウンロードの確認
    private func handleDownloadFrom(_ item: DriveItem) {
        guard !blockIfOffline() else { return }
        selectedItemForCascade = item
        showingCascadeDownloadConfirmation = true
    }

    /// メニュー: 試し読み（全シリーズの1巻をダウンロード）の確認
    private func handleTrialDownload() {
        guard !blockIfOffline() else { return }
        guard !downloadQueue.isTrialEnqueueInProgress else {
            statusCenter.show(ToastData(
                title: "試し読みダウンロード",
                message: "現在処理中です。しばらくお待ちください。",
                type: .info
            ))
            return
        }
        showingTrialDownloadConfirmation = true
    }

    private func handleItemTap(_ item: DriveItem) {
        if item.isFolder {
            Task { await libraryViewModel.navigateToFolder(item) }
        } else if item.isArchive {
            // ダウンロード済みか確認
            if let existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: item.id),
               existingComic.status == .completed {
                // ダウンロード済み → 直接リーダーを開く
                readingSession = ComicSession(source: LocalComicSource(comic: existingComic))
            } else {
                // 未ダウンロード → ダウンロードシートを表示
                if authViewModel.isOfflineMode {
                    statusCenter.show(ToastData(
                        title: "オフラインモード",
                        message: "この漫画はオフラインでは閲覧できません。",
                        type: .error
                    ))
                } else {
                    selectedItem = item
                }
            }
        } else if item.isImage {
            // 画像ファイルはストリーミング閲覧開始
            if authViewModel.isOfflineMode {
                statusCenter.show(ToastData(
                    title: "オフラインモード",
                    message: "この漫画はオフラインでは閲覧できません。",
                    type: .error
                ))
            } else {
                startStreamingRead(from: item)
            }
        }
    }
    
    /// ストリーミング閲覧を開始
    private func startStreamingRead(from item: DriveItem) {
        // 現在のフォルダ内の全画像を取得
        let images = libraryViewModel.items.filter { $0.isImage }
        guard !images.isEmpty else { return }
        
        // アクセストークンをセット（重要: これがないと画像データがダウンロードできない）
        libraryViewModel.driveService.setAccessToken(authViewModel.accessToken)
        
        // タップした画像のインデックスを特定
        let initialIndex = images.firstIndex(where: { $0.id == item.id }) ?? 0
        
        // RemoteComicSourceを作成
        let source = RemoteComicSource(
            folderId: libraryViewModel.currentFolderId ?? "root",
            title: libraryViewModel.currentFolderName,
            files: images,
            driveService: libraryViewModel.driveService,
            parentId: libraryViewModel.folderPath.dropLast().last?.id
        )
        
        // 初期ページを設定
        Task {
            await source.saveProgress(page: initialIndex)
            await MainActor.run {
                readingSession = ComicSession(source: source)
            }
        }
    }
}

// MARK: - Grid Cell

/// グリッド表示用セル
struct DriveItemGridCell: View {
    let item: DriveItem
    let isBulkDownloading: Bool
    let localComic: LocalComic?
    let seriesThumbnailURL: URL?

    private var isDownloaded: Bool { localComic != nil }
    private var localThumbnailURL: URL? { localComic?.imagePaths.first }
    private var readingProgress: Double { localComic?.readingProgress ?? 0.0 }

    var body: some View {
        VStack(spacing: 8) {
            // サムネイル / アイコン
            // 正方形の背景をレイアウトの基準とし、画像はoverlayで重ねてクリップする
            // （scaledToFillはframe制約なしだと横長画像でレイアウトがセル外へ広がり、
            //   隣のセルに被ってしまうため）
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    thumbnailContent
                }
                .overlay {
                    // 読了プログレスバー
                    if isDownloaded && readingProgress > 0 {
                        VStack {
                            Spacer()
                            ProgressView(value: readingProgress)
                                .progressViewStyle(.linear)
                                .tint(.appProgressTint)
                                .background(Color.white.opacity(0.8))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .overlay(alignment: .topTrailing) {
                    if isBulkDownloading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .appProgressTint))
                            .background(Circle().fill(.white).frame(width: 24, height: 24).shadow(radius: 2))
                            .offset(x: 4, y: -4)
                    } else if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.appDownloadedBadge)
                            .background(Circle().fill(.white).frame(width: 18, height: 18))
                            .offset(x: 4, y: -4)
                    }
                }

            // ファイル名（作品名と巻数・作者名を改行して表示）
            // 補足行がないセルにも同じ高さを確保し、グリッド行の下端を揃える
            let displayName = item.displayName
            VStack(spacing: 2) {
                Text(displayName.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(displayName.subtitle ?? " ")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            // サイズ
            if !item.isFolder {
                Text(item.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
    }

    /// サムネイル画像（優先順: ファイル自身のDriveサムネ → ローカル1ページ目 → シリーズサムネ → アイコン）
    /// はみ出しのクリップは呼び出し側（正方形背景のoverlay + clipShape）で行う
    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL = item.thumbnailURL {
            KFImage(thumbnailURL)
                .resizable()
                .scaledToFill()
        } else if let localThumbnailURL = localThumbnailURL {
            KFImage(localThumbnailURL)
                .resizable()
                .scaledToFill()
        } else if item.isFolder, let seriesThumbnailURL = seriesThumbnailURL {
            // シリーズ（1巻）の永続サムネイル
            KFImage(seriesThumbnailURL)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: item.iconName)
                .font(.system(size: 40))
                .foregroundColor(iconColor)
        }
    }

    private var iconColor: Color {
        if item.isFolder {
            return .accentColor
        } else if item.isArchive {
            return .appWarning
        } else if Config.SupportedFormats.imageExtensions.contains(item.fileExtension.lowercased()) {
            return .purple
        }
        return .gray
    }
}

// MARK: - List Row

/// リスト表示用行
struct DriveItemListRow: View {
    let item: DriveItem
    let isBulkDownloading: Bool
    let localComic: LocalComic?
    let seriesThumbnailURL: URL?

    private var isDownloaded: Bool { localComic != nil }
    private var localThumbnailURL: URL? { localComic?.imagePaths.first }
    private var readingProgress: Double { localComic?.readingProgress ?? 0.0 }

    var body: some View {
        HStack(spacing: 12) {
            // アイコン
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 44, height: 44)

                if let localThumbnailURL = localThumbnailURL {
                    KFImage(localThumbnailURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else if item.isFolder, let seriesThumbnailURL = seriesThumbnailURL {
                    // シリーズ（1巻）の永続サムネイル
                    KFImage(seriesThumbnailURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Image(systemName: item.iconName)
                        .font(.title3)
                        .foregroundColor(iconColor)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isBulkDownloading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .appProgressTint))
                        .background(Circle().fill(.white).frame(width: 16, height: 16).shadow(radius: 1))
                        .offset(x: 2, y: -2)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.appDownloadedBadge)
                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                        .offset(x: 2, y: -2)
                }
            }
            
            // ファイル情報（作品名と巻数・作者名を改行して表示）
            let displayName = item.displayName
            VStack(alignment: .leading, spacing: 2) {
                // タイトルと補足行はVoiceOverで1つの要素として読み上げる
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName.title)
                        .font(.body)
                        .lineLimit(1)

                    if let subtitle = displayName.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)

                if isDownloaded && readingProgress > 0 {
                    ProgressView(value: readingProgress)
                        .progressViewStyle(.linear)
                        .tint(.appProgressTint)
                        .frame(height: 4)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }
                
                HStack {
                    if !item.isFolder {
                        Text(item.formattedSize)
                    }
                    if let modifiedTime = item.modifiedTime {
                        Text(modifiedTime, style: .date)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 矢印
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var iconColor: Color {
        if item.isFolder {
            return .accentColor
        } else if item.isArchive {
            return .appWarning
        } else if Config.SupportedFormats.imageExtensions.contains(item.fileExtension.lowercased()) {
            return .purple
        }
        return .gray
    }
}

#Preview {
    LibraryView()
        .environment(AuthViewModel())
        .environment(StatusCenter.shared)
}

// MARK: - View Modifiers

struct AlertsAndSheetsModifier: ViewModifier {
    @Binding var showingSignOutAlert: Bool
    @Binding var showingBulkDownloadConfirmation: Bool
    @Binding var selectedItem: DriveItem?
    @Binding var selectedFolderForBulk: DriveItem?
    @Binding var showingCascadeDownloadConfirmation: Bool
    @Binding var selectedItemForCascade: DriveItem?
    @Binding var showingTrialDownloadConfirmation: Bool
    @Binding var readingSession: LibraryView.ComicSession?

    @Environment(StatusCenter.self) private var statusCenter

    let authViewModel: AuthViewModel
    let libraryViewModel: LibraryViewModel

    /// 「次のDriveアイテムを開く」処理で現在受理中の（進行中の）リクエストのアイテムID。
    /// 非nilは「このIDのリクエストが進行中」を意味し、完了・失敗・割り込みなどの
    /// 終端に達したら必ずnilに戻す。用途は2つ:
    /// - フォルダ内一覧取得（非同期）中に別の遷移リクエストが割り込んだ場合、
    ///   古いリクエストがreadingSessionを上書きしてしまうのを防ぐ
    /// - 同じアイテムへのリクエストの多重実行（ボタン連打）を防ぐ
    @State private var pendingOpenNextDriveItemID: String?

    /// リーダーからの「次の巻を開く」要求を処理する。
    /// fullScreenCoverは閉じず、readingSessionを直接差し替える。
    /// （`.id(session.id)` により ReaderView と ReaderViewModel は作り直されるため、
    ///   カバーを一度閉じて再表示する必要はなく、黒画面のギャップが発生しない）
    private func handleOpenNext(_ target: NextVolumeTarget) {
        switch target {
        case .local(var nextComic):
            // 進行中のDriveフォルダ取得があれば、この新しい要求で無効化する
            pendingOpenNextDriveItemID = nil
            // 次の巻は1ページ目から表示する
            nextComic.lastReadPage = 0
            readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: nextComic))
        case .drive(let nextItem):
            handleOpenNextDriveItem(nextItem)
        }
    }

    /// リーダーからの「次のDriveアイテムを開く」要求を処理する
    private func handleOpenNextDriveItem(_ nextItem: DriveItem) {
        // 同じアイテムへの要求が既に進行中なら無視する（「次を読む」連打での
        // フォルダ一覧取得の多重実行を防ぐ）
        guard pendingOpenNextDriveItemID != nextItem.id else { return }

        // 要求受付時点でリクエストIDと現在のフォルダIDをスナップショットする
        // （フォルダ内一覧の取得中にさらに新しい遷移が発生しても影響を受けないようにするため）
        let requestID = nextItem.id
        let parentId = libraryViewModel.currentFolderId
        pendingOpenNextDriveItemID = requestID

        if authViewModel.isOfflineMode {
            openNextDriveItemOffline(nextItem)
        } else {
            openNextDriveItemOnline(nextItem, requestID: requestID, parentId: parentId)
        }
    }

    /// オフラインモード時: ダウンロード済みアーカイブのみ開ける
    private func openNextDriveItemOffline(_ nextItem: DriveItem) {
        // 同期的に完結するのでリクエストはここで終端に達する
        pendingOpenNextDriveItemID = nil

        if nextItem.isArchive,
           var existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: nextItem.id),
           existingComic.status == .completed {
            // 次の巻は1ページ目から表示する
            existingComic.lastReadPage = 0
            readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: existingComic))
        } else {
            // 未ダウンロードのアーカイブ、またはフォルダ/画像はオフライン表示不可。
            // トーストのオーバーレイはfullScreenCover（リーダー）の下に隠れるため、
            // カバーを閉じてから出す（この順序を維持すること）
            readingSession = nil
            statusCenter.show(ToastData(
                title: "オフラインモード",
                message: "この漫画はオフラインでは閲覧できません。",
                type: .error
            ))
        }
    }

    /// オンライン時: アイテムの種類に応じてソースを構築する
    private func openNextDriveItemOnline(_ nextItem: DriveItem, requestID: String, parentId: String?) {
        if nextItem.isFolder {
            openNextFolder(nextItem, requestID: requestID, parentId: parentId)
        } else if nextItem.isImage {
            openNextImage(nextItem, parentId: parentId)
        } else if nextItem.isArchive {
            openNextArchive(nextItem)
        }
    }

    /// 次の巻がフォルダ（画像ストリーミング）の場合
    private func openNextFolder(_ nextItem: DriveItem, requestID: String, parentId: String?) {
        // フォルダ内の画像一覧を取得してからソースを構築する
        // （空のfilesを渡すとpageCount=0のまま固定されてしまうため）
        // 取得が終わるまでは現在の巻を表示したままにし、完了時にセッションを差し替える
        Task { @MainActor in
            var allItems: [DriveItem] = []
            var token: String?
            do {
                repeat {
                    let result = try await libraryViewModel.driveService.listFiles(
                        in: nextItem.id,
                        pageToken: token
                    )
                    allItems.append(contentsOf: result.items)
                    token = result.nextPageToken
                } while token != nil
            } catch {
                // 取得中に別の遷移リクエストが割り込んでいた場合は何もしない
                guard pendingOpenNextDriveItemID == requestID else { return }
                // ここでリクエストは終端に達する
                pendingOpenNextDriveItemID = nil
                // 取得中にユーザーがリーダーを手動で閉じていた場合は、
                // もう関心のないエラートーストを出さない
                guard readingSession != nil else { return }
                // トーストのオーバーレイはfullScreenCover（リーダー）の下に隠れるため、
                // カバーを閉じてから出す（この順序を維持すること）
                readingSession = nil
                statusCenter.show(ToastData(
                    title: "読み込み失敗",
                    message: error.localizedDescription,
                    type: .error
                ))
                return
            }

            // 取得中に別の遷移リクエストが割り込んでいた場合は、それを上書きしない
            guard pendingOpenNextDriveItemID == requestID else { return }
            // ここでリクエストは終端に達する（以降は成功/空フォルダのいずれか）
            pendingOpenNextDriveItemID = nil
            // 取得中にユーザーがリーダーを手動で閉じていた場合（readingSession == nil）、
            // このリクエストはもう無効。ここで開き直すと閉じたはずのリーダーが
            // 勝手に復活してしまうため何もしない
            guard readingSession != nil else { return }

            let images = allItems.filter { $0.isImage }
            guard !images.isEmpty else {
                // トーストのオーバーレイはfullScreenCover（リーダー）の下に隠れるため、
                // カバーを閉じてから出す（この順序を維持すること）
                readingSession = nil
                statusCenter.show(ToastData(
                    title: "ダウンロード",
                    message: "この巻には画像が含まれていません",
                    type: .error
                ))
                return
            }

            let source = RemoteComicSource(
                folderId: nextItem.id,
                title: nextItem.name,
                files: images,
                driveService: libraryViewModel.driveService,
                parentId: parentId
            )
            readingSession = LibraryView.ComicSession(source: source)
        }
    }

    /// 次の巻が単独画像の場合
    private func openNextImage(_ nextItem: DriveItem, parentId: String?) {
        // 同期的に完結するのでリクエストはここで終端に達する
        pendingOpenNextDriveItemID = nil

        // idは画像自身のものを使う（親フォルダIDを使うと、同じフォルダ内の
        // 別画像へ連続ジャンプした際にidが変化せず、状態リセットも次巻検出も機能しなくなる）
        let source = RemoteComicSource(
            folderId: nextItem.id,
            title: nextItem.name,
            files: [nextItem],
            driveService: libraryViewModel.driveService,
            parentId: parentId
        )
        readingSession = LibraryView.ComicSession(source: source)
    }

    /// 次の巻がアーカイブの場合
    private func openNextArchive(_ nextItem: DriveItem) {
        // アーカイブの場合はダウンロード済みかチェック
        if var existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: nextItem.id),
           existingComic.status == .completed {
            // 同期的に完結するのでリクエストはここで終端に達する
            pendingOpenNextDriveItemID = nil
            // 次の巻は1ページ目から表示する
            existingComic.lastReadPage = 0
            readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: existingComic))
        } else {
            // 未ダウンロードの場合はDownloadSheet（selectedItemのsheet）で案内する。
            // このパスだけはセッションの差し替えではなくsheet表示が必要であり、
            // fullScreenCoverが表示されたままsheetは出せないため、明示的にカバーを
            // 閉じてから、dismissアニメーションの完了を待ってsheetを表示する
            // （同時に行うと表示が競合してsheetが出ないことがある）
            let requestID = nextItem.id
            readingSession = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // 待機中に別の遷移リクエストが割り込んでいた場合は何もしない
                guard pendingOpenNextDriveItemID == requestID else { return }
                // ここでリクエストは終端に達する
                pendingOpenNextDriveItemID = nil
                guard readingSession == nil else { return }
                selectedItem = nextItem
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AllComicsDeleted"))) { _ in
                // ストレージ管理画面での全削除を反映する（downloadedComics/seriesThumbnailsの
                // 前段キャッシュが削除済みファイルのURLを保持し続けないようにする）
                libraryViewModel.refreshDownloadedComics()
                libraryViewModel.invalidateAllSeriesThumbnails()
            }
            .alert("サインアウト", isPresented: $showingSignOutAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("サインアウト", role: .destructive) {
                    authViewModel.signOut()
                }
            } message: {
                Text("サインアウトしますか？")
            }
            .alert("シリーズ一括ダウンロード", isPresented: $showingBulkDownloadConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ダウンロード") {
                    guard let folder = selectedFolderForBulk else { return }
                    Task { @MainActor in
                        do {
                            let added = try await DownloadQueueManager.shared.enqueueSeries(folder: folder)
                            if added > 0 {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード開始",
                                    message: "\(folder.name) の\(added)件をキューに追加しました",
                                    type: .info
                                ))
                            } else {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード",
                                    message: "追加できるファイルがありません（ダウンロード済み）",
                                    type: .info
                                ))
                            }
                        } catch {
                            statusCenter.show(ToastData(
                                title: "ダウンロード失敗",
                                message: error.localizedDescription,
                                type: .error
                            ))
                        }
                    }
                }
            } message: {
                if let folder = selectedFolderForBulk {
                    Text("\(folder.name)内のアーカイブをバックグラウンドで一括ダウンロードします。")
                }
            }
            .alert("この巻以降をダウンロード", isPresented: $showingCascadeDownloadConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ダウンロード") {
                    guard let item = selectedItemForCascade,
                          let folderId = libraryViewModel.currentFolderId else { return }
                    Task { @MainActor in
                        do {
                            let (added, total) = try await DownloadQueueManager.shared.enqueueFrom(
                                folderId: folderId,
                                item: item
                            )
                            if added > 0 {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード開始",
                                    message: "\(item.name)以降の\(added)件をキューに追加しました",
                                    type: .info
                                ))
                            } else if total > 0 {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード",
                                    message: "追加できるファイルがありません（ダウンロード済み）",
                                    type: .info
                                ))
                            } else {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード失敗",
                                    message: "対象の巻が見つかりませんでした",
                                    type: .error
                                ))
                            }
                        } catch {
                            statusCenter.show(ToastData(
                                title: "ダウンロード失敗",
                                message: error.localizedDescription,
                                type: .error
                            ))
                        }
                    }
                }
            } message: {
                if let item = selectedItemForCascade {
                    Text("「\(item.name)」以降のアーカイブをバックグラウンドでダウンロードします。")
                }
            }
            .alert("試し読みダウンロード", isPresented: $showingTrialDownloadConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ダウンロード") {
                    Task { @MainActor in
                        do {
                            let (added, seriesCount, candidateCount) =
                                try await DownloadQueueManager.shared.enqueueTrialVolumes()
                            if added > 0 {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード開始",
                                    message: "\(seriesCount)シリーズ中\(added)件の1巻をキューに追加しました",
                                    type: .info
                                ))
                            } else if candidateCount > 0 {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード",
                                    message: "追加できるファイルがありません（ダウンロード済み）",
                                    type: .info
                                ))
                            } else if seriesCount > 0 {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード",
                                    message: "対象のアーカイブが見つかりませんでした",
                                    type: .error
                                ))
                            } else {
                                statusCenter.show(ToastData(
                                    title: "ダウンロード",
                                    message: "シリーズフォルダが見つかりませんでした",
                                    type: .info
                                ))
                            }
                        } catch {
                            statusCenter.show(ToastData(
                                title: "ダウンロード失敗",
                                message: error.localizedDescription,
                                type: .error
                            ))
                        }
                    }
                }
            } message: {
                Text("全シリーズの1巻をバックグラウンドで一括ダウンロードします。シリーズ数が多い場合は時間がかかることがあります。")
            }
            .sheet(item: $selectedItem) { item in
                // ダウンロードターゲットを決定
                let target: DownloadTarget = {
                    if item.isArchive {
                        return .file(item)
                    } else {
                        // 画像ファイルの場合は親フォルダをダウンロード
                        return .folder(
                            id: libraryViewModel.currentFolderId ?? "root",
                            name: libraryViewModel.currentFolderName
                        )
                    }
                }()
                
                DownloadSheet(
                    target: target,
                    isPresented: Binding(
                        get: { self.selectedItem != nil },
                        set: { if !$0 { self.selectedItem = nil } }
                    ),
                    onComplete: { comic in
                        // ローカルコミックとして開く
                        self.selectedItem = nil
                        readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: comic))
                    }
                )
            }
            .fullScreenCover(item: $readingSession) { session in
                // 「次の巻」への遷移はカバーを閉じずにitem（readingSession）を
                // 直接差し替えることで行う（fullScreenCover(item:)は表示中のitem変更を
                // dismiss+再表示ではなく中身の差し替えとして扱うため、黒画面が出ない）。
                // sessionのidが変わるたびにReaderViewとその@State（ReaderViewModel）を
                // 強制的に作り直す。これがないと古いReaderViewModel（＝古いページ数）が
                // 使い回されてしまう
                ReaderView(source: session.source, onOpenNext: handleOpenNext)
                    .id(session.id)
            }
    }
}
