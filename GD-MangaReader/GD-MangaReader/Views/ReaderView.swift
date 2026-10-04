// ReaderView.swift
// GD-MangaReader
//
// 漫画閲覧画面 - 横読み（RTL/LTR）、縦読み、ズーム、見開き表示対応
//

import SwiftUI

/// リーダーから「次の巻」として開く対象
enum NextVolumeTarget {
    case local(LocalComic)
    case drive(DriveItem)
}

/// 上端Safe Areaインセットの実測値を伝搬するPreferenceKey。
/// リーダー本体は全画面（.ignoresSafeArea()）で描画するため、その内側では
/// safeAreaInsetsが取得できない。Safe Areaを無視しないbackgroundプローブから
/// この値を受け取り、ヘッダーの上端パディングに使う
private struct SafeAreaTopInsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 漫画閲覧画面
struct ReaderView: View {
    let source: any ComicSource
    /// 「次を読む」時に呼ばれるコールバック。
    /// 呼び出し側（LibraryView）がreadingSessionを直接差し替えることで、
    /// fullScreenCoverを閉じずにリーダーの中身だけを次の巻に切り替える
    let onOpenNext: (NextVolumeTarget) -> Void
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    /// 「読了後に自動削除」を初めて有効化する際の確認アラート表示フラグ
    @State private var showingAutoDeleteConfirmation = false

    /// 自動削除の初回確認を済ませたかどうかのUserDefaultsキー
    /// （一度確認したら、以降のON/OFF切り替えでは確認を出さない）
    private static let autoDeleteConfirmedKey = "reader.autoDeleteConfirmed"

    /// タップゾーンの説明オーバーレイを表示済みかどうかのUserDefaultsキー
    /// （アプリ全体で初回のリーダー起動時に一度だけ表示する）
    private static let tapZoneHintShownKey = "reader.tapZoneHintShown"

    /// タップゾーン説明オーバーレイの表示フラグ（約3秒 or タップで消える）
    @State private var showTapZoneHint = false

    /// タップゾーン説明の自動消去タスク（タップによる早期消去・画面離脱時にキャンセルする）
    @State private var hintDismissTask: Task<Void, Never>?

    /// ヘッダーをステータスバー/ノッチと被らせないための上端Safe Area実測値。
    /// 外側のGeometryReaderには.ignoresSafeArea()が適用されているため、その
    /// proxy.safeAreaInsetsは0を返す（実機/シミュレータで確認済み）。そのため
    /// Safe Areaを無視しないbackgroundプローブで実測した値をここに保持する
    @State private var safeAreaTopInset: CGFloat = 0

    init(source: any ComicSource, onOpenNext: @escaping (NextVolumeTarget) -> Void = { _ in }) {
        self.source = source
        self.onOpenNext = onOpenNext
        self._viewModel = State(initialValue: ReaderViewModel(source: source))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.black.ignoresSafeArea()
                
                // ページコンテンツ
                switch viewModel.readingMode {
                case .horizontal:
                    horizontalReader(geometry: geometry)
                case .vertical:
                    verticalReader(geometry: geometry)
                }
                
                // UIオーバーレイ
                if viewModel.showUI {
                    uiOverlay(topInset: safeAreaTopInset)
                }
                
                // 次の巻サジェスト
                if viewModel.showNextVolumeSuggestion {
                    if let nextComic = viewModel.nextComic {
                        nextVolumeOverlay(nextComic: nextComic)
                    } else if let nextDriveItem = viewModel.nextDriveItem {
                        nextVolumeOverlayForDrive(item: nextDriveItem)
                    }
                }

                // 初回起動時のみのタップゾーン説明オーバーレイ
                if showTapZoneHint {
                    tapZoneHintOverlay(size: geometry.size)
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                // ヒント表示中のタップはヒントを閉じるだけ（ページ送りしない）
                if showTapZoneHint {
                    hintDismissTask?.cancel()
                    hintDismissTask = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTapZoneHint = false
                    }
                    return
                }
                handleTap(at: location, in: geometry.size)
            }
            // VoiceOver向け: 視覚的なタップゾーンの代替となるカスタムアクション。
            // デフォルトアクション（ダブルタップ）はメニューの表示切替に割り当てる
            .accessibilityAction {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showUI.toggle()
                }
            }
            .accessibilityAction(named: "次のページ") {
                viewModel.goToNextPage()
            }
            .accessibilityAction(named: "前のページ") {
                viewModel.goToPreviousPage()
            }
            .onAppear {
                viewModel.isLandscape = geometry.size.width > geometry.size.height
                presentTapZoneHintIfNeeded()
            }
            .onDisappear {
                hintDismissTask?.cancel()
                hintDismissTask = nil
                viewModel.cleanup()
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.isLandscape = newSize.width > newSize.height
            }
            .onChange(of: viewModel.currentPage) { _, _ in
                saveProgress()
                viewModel.checkIfLastPageReached()
                viewModel.prefetchImages()
            }
        }
        .ignoresSafeArea()
        // 上端Safe Areaの実測プローブ。
        // .ignoresSafeArea()より外側（Safe Areaが消費されていない座標系）に付けることで、
        // proxy.safeAreaInsets.topが実デバイスの上端インセットを返す
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: SafeAreaTopInsetPreferenceKey.self,
                        value: proxy.safeAreaInsets.top
                    )
            }
        )
        .onPreferenceChange(SafeAreaTopInsetPreferenceKey.self) { inset in
            safeAreaTopInset = inset
        }
        .statusBarHidden(!viewModel.showUI)
        .focusable()
        .onKeyPress(.leftArrow) {
            handleLeftKey()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleRightKey()
            return .handled
        }
        .onKeyPress(.space) {
            viewModel.goToNextPage()
            return .handled
        }
        .alert("読了後に自動削除", isPresented: $showingAutoDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("有効にする") {
                UserDefaults.standard.set(true, forKey: Self.autoDeleteConfirmedKey)
                viewModel.autoDeleteAfterRead = true
            }
        } message: {
            Text("読み終えた巻を自動的に削除します。よろしいですか？")
        }
    }
    
    // MARK: - Horizontal Reader (Left/Right Swipe)
    
    @ViewBuilder
    private func horizontalReader(geometry: GeometryProxy) -> some View {
        TabView(selection: $viewModel.currentPage) {
            ForEach(viewModel.pageIndices, id: \.self) { index in
                Group {
                    if viewModel.isSpreadMode && !viewModel.widePageIndices.contains(index) {
                        spreadPageView(index: index, geometry: geometry)
                    } else {
                        singlePageView(index: index, geometry: geometry)
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 設定変更時にTabViewを再生成して確実に反映させる
        .id("ReaderTabView_\(viewModel.isSpreadMode)_\(viewModel.isSpreadSwapped)_\(viewModel.isSpreadShifted)_\(viewModel.isRightToLeft)_\(viewModel.isSpreadGapRemoved)")
        .ignoresSafeArea()
        .environment(\.layoutDirection, viewModel.isRightToLeft ? .rightToLeft : .leftToRight)
    }
    
    // MARK: - Vertical Reader (Scroll)
    
    @ViewBuilder
    private func verticalReader(geometry: GeometryProxy) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.pageRange, id: \.self) { index in
                        // vertical pages
                        ZoomableImageView(
                            source: source,
                            index: index,
                            geometry: geometry,
                            currentPage: viewModel.currentPage
                        )
                        .id(index)
                    }
                }
            }
            .onChange(of: viewModel.currentPage) { _, newPage in
                withAnimation {
                    scrollProxy.scrollTo(newPage, anchor: .top)
                }
            }
        }
    }
    
    // MARK: - Single Page View
    
    @ViewBuilder
    private func singlePageView(index: Int, geometry: GeometryProxy) -> some View {
        ZoomableImageView(
            source: source,
            index: index,
            geometry: geometry,
            currentPage: viewModel.currentPage
        )
    }
    
    // MARK: - Spread Page View (Two pages side by side)
    
    @ViewBuilder
    private func spreadPageView(index: Int, geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let (leftIndex, rightIndex) = viewModel.getSpreadIndices(for: index)
            
            if let leftIndex = leftIndex {
                ZoomableImageView(
                    source: source,
                    index: leftIndex,
                    geometry: geometry,
                    isHalfWidth: true,
                    alignment: viewModel.isSpreadGapRemoved ? .trailing : .center,
                    currentPage: viewModel.currentPage
                )
            } else {
                Color.black
                    .frame(width: geometry.size.width / 2)
            }
            
            if let rightIndex = rightIndex {
                ZoomableImageView(
                    source: source,
                    index: rightIndex,
                    geometry: geometry,
                    isHalfWidth: true,
                    alignment: viewModel.isSpreadGapRemoved ? .leading : .center,
                    currentPage: viewModel.currentPage
                )
            } else {
                Color.black
                    .frame(width: geometry.size.width / 2)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isPreparingNextVolume {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.readerAccent)
                    Text("次の巻を確認中...")
                        .font(.caption)
                        .foregroundColor(.readerAccent)
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Tap Zone Hint (First Launch Only)

    /// 初回リーダー起動時にのみ表示するタップゾーンの説明。
    /// 約3秒後、または画面タップで消える（タップはZStackのonTapGestureが吸収する）
    private func presentTapZoneHintIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.tapZoneHintShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.tapZoneHintShownKey)
        withAnimation(.easeInOut(duration: 0.2)) {
            showTapZoneHint = true
        }
        hintDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            // タップによる早期消去や画面離脱でキャンセルされた場合は何もしない
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showTapZoneHint = false
            }
        }
    }

    /// タップゾーン（左25% / 中央50% / 右25%）の視覚的な説明オーバーレイ。
    /// 左右のラベルはhandleTapの実際の挙動（isRightToLeftで反転）に合わせる
    private func tapZoneHintOverlay(size: CGSize) -> some View {
        HStack(spacing: 0) {
            tapZoneHintLabel(
                title: viewModel.isRightToLeft ? "次のページ" : "前のページ",
                icon: "arrow.left"
            )
            .frame(width: size.width * 0.25)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.08))

            tapZoneHintLabel(title: "メニュー", icon: "hand.tap")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            tapZoneHintLabel(
                title: viewModel.isRightToLeft ? "前のページ" : "次のページ",
                icon: "arrow.right"
            )
            .frame(width: size.width * 0.25)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.08))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.6))
        .transition(.opacity)
        .accessibilityHidden(true) // VoiceOverにはカスタムアクションで案内済みのため隠す
    }

    private func tapZoneHintLabel(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.white)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - UI Overlay

    private func uiOverlay(topInset: CGFloat) -> some View {
        VStack {
            // ヘッダー
            headerBar
                // ステータスバーと被らないようにTopのSafe Area実測値
                // （backgroundプローブで計測したsafeAreaTopInset）を使う
                .padding(.top, topInset)

            Spacer()

            // フッター
            footerBar
        }
        .transition(.opacity)
        .edgesIgnoringSafeArea(.all) // 背景グラデーションを端まで伸ばすために全体は無視させる
    }
    
    private var headerBar: some View {
        HStack {
            Button {
                Task {
                    await saveProgress()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            }
            .accessibilityLabel("閉じる")
            
            Spacer()
            
            Text(source.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            settingsMenu
        }
        .padding(.horizontal)
        .padding(.top, 8) // Safe Area分の調整はbackground内で行うか、ここで行う
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.top) // グラデーションはSafe Areaまで伸ばす
            .frame(height: 140) // 高さを少し増やす
            .allowsHitTesting(false),
            alignment: .top
        )
    }
    
    private var settingsMenu: some View {
        Menu {
            // 読み方向
            Section("読み方向") {
                Toggle("右から左（日本式）", isOn: Binding(
                    get: { viewModel.isRightToLeft },
                    set: { viewModel.isRightToLeft = $0 }
                ))
            }
            
            // 読み方モード
            Section("表示モード") {
                Picker("表示モード", selection: Binding(
                    get: { viewModel.readingMode },
                    set: { viewModel.readingMode = $0 }
                )) {
                    Text("横読み").tag(ReadingMode.horizontal)
                    Text("縦読み").tag(ReadingMode.vertical)
                }
            }
            
            // 見開き表示（横向き時のみ有効）
            if viewModel.isLandscape {
                Section {
                    Toggle("見開き表示", isOn: Binding(
                        get: { viewModel.isSpreadEnabled },
                        set: { viewModel.isSpreadEnabled = $0 }
                    ))
                    if viewModel.isSpreadEnabled {
                        Toggle("左右入れ替え", isOn: Binding(
                            get: { viewModel.isSpreadSwapped },
                            set: { viewModel.isSpreadSwapped = $0 }
                        ))
                        Toggle("半ページずらす", isOn: Binding(
                            get: { viewModel.isSpreadShifted },
                            set: { viewModel.isSpreadShifted = $0 }
                        ))
                        Toggle("中央寄せ（空白除去）", isOn: Binding(
                            get: { viewModel.isSpreadGapRemoved },
                            set: { viewModel.isSpreadGapRemoved = $0 }
                        ))
                    }
                }
            }
            
            Section("自動スクロール") {
                Toggle("自動スクロール", isOn: Binding(
                    get: { viewModel.isAutoScrollEnabled },
                    set: { viewModel.isAutoScrollEnabled = $0 }
                ))
                if viewModel.isAutoScrollEnabled {
                    Picker("間隔", selection: Binding(
                        get: { viewModel.autoScrollInterval },
                        set: { viewModel.autoScrollInterval = $0 }
                    )) {
                        ForEach(1...10, id: \.self) { second in
                            Text("\(second)秒").tag(second)
                        }
                    }
                }
            }
            
            Section("一般設定") {
                Toggle("読了後に自動削除", isOn: Binding(
                    get: { viewModel.autoDeleteAfterRead },
                    set: { newValue in
                        // ファイル削除を伴う設定のため、初回の有効化時のみ確認アラートを挟む
                        // （確認済みならUserDefaultsのフラグによりそのまま切り替える）
                        if newValue && !UserDefaults.standard.bool(forKey: Self.autoDeleteConfirmedKey) {
                            showingAutoDeleteConfirmation = true
                        } else {
                            viewModel.autoDeleteAfterRead = newValue
                        }
                    }
                ))
            }
        } label: {
            Image(systemName: "gearshape")
            .font(.title2)
            .foregroundColor(.white)
            .padding()
        }
        .accessibilityLabel("表示設定")
    }
    
    private var footerBar: some View {
        VStack(spacing: 12) {
            // ページスライダー
            HStack {
                Text("\(viewModel.currentPage + 1)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 40)
                
                Slider(
                    value: Binding(
                        get: { Double(viewModel.currentPage) },
                        set: { viewModel.currentPage = viewModel.normalizePageIndex(Int($0)) }
                    ),
                    in: 0...Double(max(0, source.pageCount - 1)),
                    step: 1
                )
                .tint(.readerAccent)
                .environment(\.layoutDirection, viewModel.isRightToLeft ? .rightToLeft : .leftToRight)
                .accessibilityLabel("ページ")
                .accessibilityValue("\(viewModel.currentPage + 1) / \(source.pageCount) ページ")
                
                Text("\(source.pageCount)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 40)
            }
            .padding(.horizontal)
        }
        .padding()
        .padding(.bottom, 20) // Home Indicator分の余白
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.bottom)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Tap Handling
    
    private func handleTap(at location: CGPoint, in size: CGSize) {
        let leftZone = size.width * 0.25
        let rightZone = size.width * 0.75
        
        if location.x < leftZone {
            // 左タップ：前/次ページ（向きによる）
            if viewModel.isRightToLeft {
                viewModel.goToNextPage()
            } else {
                viewModel.goToPreviousPage()
            }
        } else if location.x > rightZone {
            // 右タップ：次/前ページ（向きによる）
            if viewModel.isRightToLeft {
                viewModel.goToPreviousPage()
            } else {
                viewModel.goToNextPage()
            }
        } else {
            // 中央タップ：UI表示切替
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.showUI.toggle()
            }
        }
    }
    
    // MARK: - Keyboard Handling
    
    private func handleLeftKey() {
        if viewModel.readingMode == .vertical {
            // 縦読み: 上へ？ (ページ戻り)
            viewModel.goToPreviousPage()
            return
        }
        
        if viewModel.isRightToLeft {
            // 右から左（日本式）: 左キー＝進む（次ページ）
            viewModel.goToNextPage()
        } else {
            // 左から右: 左キー＝戻る
            viewModel.goToPreviousPage()
        }
    }
    
    private func handleRightKey() {
        if viewModel.readingMode == .vertical {
            // 縦読み: 下へ？ (ページ進み)
            viewModel.goToNextPage()
            return
        }
        
        if viewModel.isRightToLeft {
            // 右から左（日本式）: 右キー＝戻る
            viewModel.goToPreviousPage()
        } else {
            // 左から右: 右キー＝進む（次ページ）
            viewModel.goToNextPage()
        }
    }
    
    // MARK: - Progress Save
    
    private func saveProgress() async {
        await source.saveProgress(page: viewModel.currentPage)
    }
    
    private func saveProgress() {
        Task {
            await saveProgress()
        }
    }
    
    // MARK: - Next Volume Suggestion View
    
    private func nextVolumeOverlay(nextComic: LocalComic) -> some View {
        suggestionContent(title: nextComic.title) {
            // 現在の巻の終了処理（自動削除など）
            await viewModel.finalizeCurrentVolume()

            // 次の巻を開く（カバーは閉じない。LibraryView側でセッションを
            // 差し替えることでリーダーの中身がそのまま次の巻に切り替わる）
            onOpenNext(.local(nextComic))
        }
    }

    private func nextVolumeOverlayForDrive(item: DriveItem) -> some View {
        suggestionContent(title: item.name) {
            // フォルダの場合は画像一覧の取得が完了するまで現在の巻が表示された
            // ままになるため、連打で同じ要求が多重に走らないよう、タップを受け
            // 付けた時点でサジェストを閉じておく
            viewModel.showNextVolumeSuggestion = false

            // リモートの場合は自動削除なし
            // 次の巻を開く（取得完了時にLibraryView側でセッションが差し替わる）
            onOpenNext(.drive(item))
        }
    }
    
    private func suggestionContent(title: String, action: @escaping () async -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("最終ページです")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
                
                VStack(spacing: 8) {
                    Text("次の巻を読みますか？")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.readerAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                HStack(spacing: 20) {
                    Button {
                        viewModel.showNextVolumeSuggestion = false
                    } label: {
                        Text("閉じる")
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(25)
                    }
                    
                    Button {
                        Task {
                            await action()
                        }
                    } label: {
                        Text("次を読む")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 32)
                            .background(Color.readerAccent)
                            .cornerRadius(25)
                    }
                }
            }
            .padding(32)
            .background(Color(white: 0.1))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(20)
        }
        .transition(.opacity)
    }
}

// MARK: - Reading Mode

enum ReadingMode: String, CaseIterable {
    case horizontal = "横読み"
    case vertical = "縦読み"
}

// MARK: - Reader ViewModel

@MainActor
@Observable
final class ReaderViewModel {
    // MARK: - Settings (Persistent)
    
    var isRightToLeft: Bool {
        didSet { 
            UserDefaults.standard.set(isRightToLeft, forKey: "isRightToLeft")
            recalculateCurrentPage()
        }
    }
    
    var readingMode: ReadingMode {
        didSet { UserDefaults.standard.set(readingMode.rawValue, forKey: "readingMode") }
    }
    
    var isSpreadEnabled: Bool {
        didSet { 
            UserDefaults.standard.set(isSpreadEnabled, forKey: "isSpreadEnabled")
            recalculateCurrentPage()
        }
    }
    
    var isSpreadSwapped: Bool {
        didSet { UserDefaults.standard.set(isSpreadSwapped, forKey: "isSpreadSwapped") }
    }
    
    var isSpreadShifted: Bool {
        didSet { 
            UserDefaults.standard.set(isSpreadShifted, forKey: "isSpreadShifted")
            recalculateCurrentPage()
        }
    }
    
    var isSpreadGapRemoved: Bool {
        didSet { UserDefaults.standard.set(isSpreadGapRemoved, forKey: "isSpreadGapRemoved") }
    }
    
    var autoDeleteAfterRead: Bool {
        didSet { UserDefaults.standard.set(autoDeleteAfterRead, forKey: "autoDeleteAfterRead") }
    }
    
    var isAutoScrollEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoScrollEnabled, forKey: "isAutoScrollEnabled")
            handleAutoScrollStateChange()
        }
    }
    
    var autoScrollInterval: Int {
        didSet {
            UserDefaults.standard.set(autoScrollInterval, forKey: "autoScrollInterval")
            if isAutoScrolling {
                resetAutoScrollTimer()
            }
        }
    }
    
    // MARK: - State
    
    var currentPage: Int {
        didSet {
            if isAutoScrollEnabled && !showUI {
                resetAutoScrollTimer()
            }
        }
    }
    
    var showUI: Bool = true {
        didSet {
            handleAutoScrollStateChange()
        }
    }
    
    var isLandscape: Bool = false {
        didSet { 
            recalculateCurrentPage()
        }
    }
    
    /// 設定や向きが変更された際に現在のページを適切な見開きインデックスに再調整する
    private func recalculateCurrentPage() {
        let normalized = normalizePageIndex(currentPage)
        if currentPage != normalized {
            currentPage = normalized
        }
    }
    
    var showNextVolumeSuggestion: Bool = false {
        didSet {
            handleAutoScrollStateChange()
        }
    }
    var isPreparingNextVolume: Bool = false
    private(set) var nextComic: LocalComic?
    private(set) var nextDriveItem: DriveItem?
    private(set) var widePageIndices: Set<Int> = []
    
    // 自動スクロール実行中ステータスとタスク
    private(set) var isAutoScrolling: Bool = false
    private var autoScrollTask: Task<Void, Never>?
    
    private var checkNextVolumeTask: Task<Void, Never>?
    private var scanWidePagesTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    
    var isSpreadMode: Bool {
        return isSpreadEnabled && isLandscape
    }
    
    private let source: any ComicSource
    
    init(source: any ComicSource) {
        self.source = source
        self.currentPage = source.lastReadPage
        
        // UserDefaults から初期値を読み込む
        self.isRightToLeft = UserDefaults.standard.bool(forKey: "isRightToLeft")
        
        let modeVal = UserDefaults.standard.string(forKey: "readingMode") ?? ReadingMode.horizontal.rawValue
        self.readingMode = ReadingMode(rawValue: modeVal) ?? .horizontal
        
        self.isSpreadEnabled = UserDefaults.standard.object(forKey: "isSpreadEnabled") as? Bool ?? true
        self.isSpreadSwapped = UserDefaults.standard.bool(forKey: "isSpreadSwapped")
        self.isSpreadShifted = UserDefaults.standard.bool(forKey: "isSpreadShifted")
        self.isSpreadGapRemoved = UserDefaults.standard.object(forKey: "isSpreadGapRemoved") as? Bool ?? true
        self.autoDeleteAfterRead = UserDefaults.standard.bool(forKey: "autoDeleteAfterRead")
        
        self.isAutoScrollEnabled = UserDefaults.standard.bool(forKey: "isAutoScrollEnabled")
        let intervalVal = UserDefaults.standard.integer(forKey: "autoScrollInterval")
        self.autoScrollInterval = intervalVal > 0 ? intervalVal : 5
        
        // 初期ページの見開き位置への調整
        recalculateCurrentPage()
        
        // ワイドページの事前スキャン
        scanWidePagesTask = Task {
            await scanWidePages()
        }
        
        // 次の巻があるか事前にチェック
        checkNextVolumeTask = Task {
            await checkForNextVolume()
            checkIfLastPageReached()
            prefetchImages()
        }
    }
    
    deinit {
        // Task cancellation moved to cleanup() called from onDisappear
    }
    
    func cleanup() {
        stopAutoScroll()
        checkNextVolumeTask?.cancel()
        scanWidePagesTask?.cancel()
        suggestionTask?.cancel()
    }
    
    // MARK: - Auto Scroll Actions
    
    func handleAutoScrollStateChange() {
        if isAutoScrollEnabled && !showUI && !showNextVolumeSuggestion {
            startAutoScroll()
        } else {
            stopAutoScroll()
        }
    }
    
    func startAutoScroll() {
        stopAutoScroll()
        guard isAutoScrollEnabled && !showNextVolumeSuggestion else { return }
        isAutoScrolling = true
        
        autoScrollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isAutoScrolling {
                // `autoScrollInterval` 秒待つ
                let safeInterval = max(1, self.autoScrollInterval)
                try? await Task.sleep(nanoseconds: UInt64(safeInterval) * 1_000_000_000)
                guard !Task.isCancelled && self.isAutoScrolling else { break }
                
                // 最終ページに到達している場合
                let lastIndex = self.pageIndices.last ?? 0
                if self.currentPage >= lastIndex {
                    // 次の巻サジェストが表示されるはずなので自動スクロールを止める
                    self.stopAutoScroll()
                    break
                }
                
                self.goToNextPage()
            }
        }
    }
    
    func stopAutoScroll() {
        isAutoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
    
    func resetAutoScrollTimer() {
        if isAutoScrollEnabled && !showUI {
            startAutoScroll()
        }
    }
    
    private func scanWidePages() async {
        let maxScanPages = source.pageCount
        let concurrencyLimit = 10 // 同時実行数を制限
        
        let widePages = await withTaskGroup(of: Int?.self) { group in
            var wideResults = Set<Int>()
            var currentIndex = 0
            
            // 最初のバッチ
            for _ in 0..<min(concurrencyLimit, maxScanPages) {
                let idx = currentIndex
                group.addTask {
                    if Task.isCancelled { return nil }
                    let isWide = await self.source.isWidePage(at: idx)
                    return isWide ? idx : nil
                }
                currentIndex += 1
            }
            
            // 残りのバッチ（一つ終わるごとに次を追加）
            for await result in group {
                if let idx = result {
                    wideResults.insert(idx)
                }
                
                if currentIndex < maxScanPages && !Task.isCancelled {
                    let nextIdx = currentIndex
                    group.addTask {
                        let isWide = await self.source.isWidePage(at: nextIdx)
                        return isWide ? nextIdx : nil
                    }
                    currentIndex += 1
                }
            }
            return wideResults
        }
        
        if Task.isCancelled { return }
        
        await MainActor.run {
            self.widePageIndices = widePages
        }
    }
    
    /// 周辺ページの画像を先読みする
    func prefetchImages() {
        let prefetchRange = 5 // 前後5ページ
        let start = max(0, currentPage - prefetchRange)
        let end = min(pageCount - 1, currentPage + prefetchRange)
        
        Task {
            for i in start...end {
                if Task.isCancelled { break }
                // すでにロード済みの場合はComicSource側でキャッシュが返るはず
                _ = try? await source.image(at: i)
            }
        }
    }
    
    private func checkForNextVolume() async {
        let currentTitle = source.title
        let pattern = "(\\s*第?\\d+[巻]?|\\s*Vol\\.?\\s*\\d+|\\s*\\(\\d+\\)|\\s+\\d+)$"
        let prefix = currentTitle.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        
        if Task.isCancelled { return }
        
        // 1. まずローカルにあるかチェック
        if let allComics = try? LocalStorageService.shared.loadComics() {
            let seriesVolumes = allComics
                .filter { $0.title.hasPrefix(prefix) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            
            if let currentIndex = seriesVolumes.firstIndex(where: { $0.id == source.id }),
               currentIndex + 1 < seriesVolumes.count {
                await MainActor.run {
                    self.nextComic = seriesVolumes[currentIndex + 1]
                }
                return
            }
        }
        
        if Task.isCancelled { return }
        
        // 2. ローカルになければリモート（Drive）を探索
        if let remoteSource = source as? RemoteComicSource, let parentId = remoteSource.parentId {
            do {
                // 親フォルダ内のアイテム一覧を取得
                let (items, _) = try await remoteSource.driveService.listFiles(in: parentId)
                
                // シリーズ判定ロジックを適用
                let seriesVolumes = items
                    .filter { $0.name.hasPrefix(prefix) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                
                // 現在のフォルダの次を探す
                if let currentIndex = seriesVolumes.firstIndex(where: { $0.id == remoteSource.id }),
                   currentIndex + 1 < seriesVolumes.count {
                    let nextItem = seriesVolumes[currentIndex + 1]
                    await MainActor.run {
                        self.nextDriveItem = nextItem
                    }
                }
            } catch {
                print("⚠️ [ReaderViewModel] Failed to fetch remote next volume: \(error.localizedDescription)")
            }
        }
    }
    
    func checkIfLastPageReached() {
        suggestionTask?.cancel()
        
        // 次の巻がない、または最終ページでない場合は表示しない
        guard let lastIndex = pageIndices.last,
              currentPage == lastIndex,
              (nextComic != nil || nextDriveItem != nil) else {
            showNextVolumeSuggestion = false
            return
        }
        
        if showNextVolumeSuggestion { return }
        
        isPreparingNextVolume = true
        
        // 1秒後にサジェストを表示
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut) {
                        isPreparingNextVolume = false
                        showNextVolumeSuggestion = true
                    }
                }
            }
        }
    }
    
    var pageCount: Int {
        source.pageCount
    }
    
    var pageRange: Range<Int> {
        0..<pageCount
    }
    
    var pageIndices: [Int] {
        if isSpreadMode {
            var indices: [Int] = []
            var current = 0
            
            // isSpreadShifted: 
            // false = 表紙(0ページ目)を単独にしてからペアリング開始 (標準)
            // true = 最初からペアリング開始
            
            if !isSpreadShifted {
                indices.append(0)
                current = 1
            } else if widePageIndices.contains(0) {
                // Shiftモードかつ0ページ目がワイドの場合、通常のロジックだと
                // 結局「0単独、1-2ペア」になり unshifted と同じになってしまう。
                // これを避けるため、1ページ目も単独にして2ページ目からペアリングを開始する。
                indices.append(0)
                if pageCount > 1 {
                    indices.append(1)
                    current = 2
                } else {
                    current = 1
                }
            }
            
            while current < pageCount {
                indices.append(current)
                
                if widePageIndices.contains(current) {
                    current += 1
                } else {
                    if current + 1 < pageCount && widePageIndices.contains(current + 1) {
                        current += 1
                    } else {
                        current += 2
                    }
                }
            }
            return indices
        } else {
            return Array(0..<pageCount)
        }
    }
    
    /// 任意のページ番号を、現在の表示モードにおける有効な開始インデックスに変換する
    func normalizePageIndex(_ page: Int) -> Int {
        guard isSpreadMode else { return max(0, min(pageCount - 1, page)) }
        
        let sortedIndices = pageIndices
        if let exact = sortedIndices.firstIndex(of: page) {
            return sortedIndices[exact]
        }
        
        // 指定ページ以下の最大のインデックスを探す
        let closest = sortedIndices.last(where: { $0 <= page }) ?? sortedIndices.first ?? 0
        return closest
    }
    
    func goToNextPage() {
        if currentPage < pageCount - 1 {
            let currentIndex = pageIndices.firstIndex(of: currentPage) ?? 0
            let newIndex = min(pageIndices.count - 1, currentIndex + 1)
            let nextPageIndex = pageIndices[newIndex]
            
            if currentPage == nextPageIndex && (nextComic != nil || nextDriveItem != nil) {
                withAnimation { showNextVolumeSuggestion = true }
            } else {
                currentPage = nextPageIndex
            }
        } else if nextComic != nil || nextDriveItem != nil {
            withAnimation { showNextVolumeSuggestion = true }
        }
    }
    
    func goToPreviousPage() {
        if showNextVolumeSuggestion {
            withAnimation { showNextVolumeSuggestion = false }
            return
        }
        
        if currentPage > 0 {
            let currentIndex = pageIndices.firstIndex(of: currentPage) ?? 0
            let newIndex = max(0, currentIndex - 1)
            currentPage = pageIndices[newIndex]
        }
    }
    
    /// 次の巻へ進む際の後処理
    func finalizeCurrentVolume() async {
        if autoDeleteAfterRead {
            if let localSource = source as? LocalComicSource {
                // LocalStorageServiceから削除
                if let comics = try? LocalStorageService.shared.loadComics(),
                   let target = comics.first(where: { $0.id == localSource.id }) {
                    try? LocalStorageService.shared.deleteComic(target)
                }
            }
        }
    }
    
    /// 見開きページのインデックスを取得（左、右）
    func getSpreadIndices(for baseIndex: Int) -> (Int?, Int?) {
        // ワイドページなら単独表示
        if widePageIndices.contains(baseIndex) {
            return (nil, baseIndex)
        }
        
        // 特殊な単独ページ判定
        if !isSpreadShifted && baseIndex == 0 {
            var left: Int? = nil, right: Int? = 0
            if !isRightToLeft { swap(&left, &right) }
            if isSpreadSwapped { swap(&left, &right) }
            return (left, right)
        }
        
        if isSpreadShifted && widePageIndices.contains(0) && baseIndex == 1 {
            // 0がワイドでShiftedの場合、1も単独表示
            var left: Int? = nil, right: Int? = 1
            if !isRightToLeft { swap(&left, &right) }
            if isSpreadSwapped { swap(&left, &right) }
            return (left, right)
        }
        
        let targetIndex = baseIndex
        let nextIndex: Int?
        if let candidate = targetIndex + 1 < pageCount ? targetIndex + 1 : nil,
           !widePageIndices.contains(candidate) {
            nextIndex = candidate
        } else {
            nextIndex = nil
        }
        
        var left: Int?, right: Int?
        if isRightToLeft {
            left = nextIndex
            right = targetIndex
        } else {
            left = targetIndex
            right = nextIndex
        }
        
        if isSpreadSwapped { swap(&left, &right) }
        return (left, right)
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let source: any ComicSource
    let index: Int
    let geometry: GeometryProxy
    var isHalfWidth: Bool = false
    var alignment: Alignment = .center
    let currentPage: Int
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    
    var body: some View {
        let imageWidth = isHalfWidth ? geometry.size.width / 2 : geometry.size.width
        
        AsyncImageView(source: source, index: index)
            .aspectRatio(contentMode: .fit)
            .frame(width: imageWidth, height: geometry.size.height, alignment: alignment)
            .clipped()
            .contentShape(Rectangle())
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture)
            .gesture(dragGesture, including: scale > 1.0 ? .all : .subviews)
            .onChange(of: currentPage) { _, newPage in
                if newPage != index {
                    if scale > 1.0 || offset != .zero {
                        withAnimation(.easeInOut) {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }
            }
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                    } else {
                        scale = 2.0
                    }
                    lastScale = scale
                    lastOffset = offset
                }
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
        .onChanged { value in
            let newScale = lastScale * value
            scale = min(max(newScale, minScale), maxScale)
        }
        .onEnded { _ in
            lastScale = scale
            if scale <= 1.0 {
                withAnimation(.spring()) {
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
        .onChanged { value in
            guard scale > 1.0 else { return }
            offset = CGSize(
                width: lastOffset.width + value.translation.width,
                height: lastOffset.height + value.translation.height
            )
        }
        .onEnded { _ in
            lastOffset = offset
        }
    }
}

// MARK: - Async Image View (From Source)

struct AsyncImageView: View {
    let source: any ComicSource
    let index: Int
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .accessibilityLabel("ページ \(index + 1) / \(source.pageCount)")
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .accessibilityLabel("ページ \(index + 1) を読み込み中")
            } else {
                // 読み込み失敗: 再読み込みボタンを提示する
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .accessibilityLabel("ページ \(index + 1) の読み込みに失敗しました")

                    Button {
                        Task {
                            await loadImage()
                        }
                    } label: {
                        Label("再読み込み", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .task {
            // すでに読み込まれた状態で再利用される場合があるためチェック
            if image == nil {
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }
        
        if let loadedImage = try? await source.image(at: index) {
            await MainActor.run {
                self.image = loadedImage
            }
        }
    }
}

#Preview {
    ReaderView(source: LocalComicSource(comic: .mock))
}
