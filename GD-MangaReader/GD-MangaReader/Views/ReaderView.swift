// ReaderView.swift
// GD-MangaReader
//
// 漫画閲覧画面 - 横読み（RTL/LTR）、縦読み、ズーム、見開き表示対応
//

import SwiftUI

/// 漫画閲覧画面
struct ReaderView: View {
    let source: any ComicSource
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(source: any ComicSource) {
        self.source = source
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
                    uiOverlay
                }
                
                // 次の巻サジェスト
                if viewModel.showNextVolumeSuggestion, let nextComic = viewModel.nextComic {
                    nextVolumeOverlay(nextComic: nextComic)
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                handleTap(at: location, in: geometry.size)
            }
            .onAppear {
                viewModel.isLandscape = geometry.size.width > geometry.size.height
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.isLandscape = newSize.width > newSize.height
            }
            .onChange(of: viewModel.currentPage) { _, _ in
                saveProgress()
            }
        }
        .ignoresSafeArea()
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
    }
    
    // MARK: - Horizontal Reader (Left/Right Swipe)
    
    @ViewBuilder
    private func horizontalReader(geometry: GeometryProxy) -> some View {
        TabView(selection: $viewModel.currentPage) {
            ForEach(viewModel.pageIndices, id: \.self) { index in
                if viewModel.isSpreadMode {
                    spreadPageView(index: index, geometry: geometry)
                        .tag(index)
                } else {
                    singlePageView(index: index, geometry: geometry)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
    }
    
    // MARK: - UI Overlay
    
    private var uiOverlay: some View {
        VStack {
            // ヘッダー
            headerBar
                // ステータスバーと被らないようにTopのSafe Areaを確保
                .padding(.top, 44) // ノッチ分の概算、またはGeometryReaderで取得推奨だが簡易対応
            
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
                Toggle("右から左（日本式）", isOn: $viewModel.isRightToLeft)
            }
            
            // 読み方モード
            Section("表示モード") {
                Picker("表示モード", selection: $viewModel.readingMode) {
                    Text("横読み").tag(ReadingMode.horizontal)
                    Text("縦読み").tag(ReadingMode.vertical)
                }
            }
            
            // 見開き表示（横向き時のみ有効）
            if viewModel.isLandscape {
                Section {
                    Toggle("見開き表示", isOn: $viewModel.isSpreadEnabled)
                    if viewModel.isSpreadEnabled {
                        Toggle("左右入れ替え", isOn: $viewModel.isSpreadSwapped)
                        Toggle("半ページずらす", isOn: $viewModel.isSpreadShifted)
                        Toggle("中央寄せ（空白除去）", isOn: $viewModel.isSpreadGapRemoved)
                    }
                }
            }
        } label: {
            Image(systemName: "gearshape")
            .font(.title2)
            .foregroundColor(.white)
            .padding()
        }
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
                .tint(.orange)
                .environment(\.layoutDirection, viewModel.isRightToLeft ? .rightToLeft : .leftToRight)
                
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
                    
                    Text(nextComic.title)
                        .font(.subheadline)
                        .foregroundColor(.orange)
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
                        // 次の巻を開く
                        // 実際には現在開いているReaderViewを閉じて、
                        // 呼び出し元で次の巻のReaderViewを開く必要がある。
                        // ここではNotificationCenterやDelegate等を使って親に通知する想定。
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenNextVolume"),
                            object: nextComic
                        )
                        dismiss()
                    } label: {
                        Text("次を読む")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 32)
                            .background(Color.orange)
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

@Observable
final class ReaderViewModel {
    var currentPage: Int
    var showUI: Bool = true
    var isRightToLeft: Bool = true
    var readingMode: ReadingMode = .horizontal
    var isSpreadEnabled: Bool = true {
        didSet { currentPage = normalizePageIndex(currentPage) }
    }
    var isSpreadSwapped: Bool = false
    var isSpreadShifted: Bool = false {
        didSet { currentPage = normalizePageIndex(currentPage) }
    }
    var isSpreadGapRemoved: Bool = true
    var isLandscape: Bool = false {
        didSet { currentPage = normalizePageIndex(currentPage) }
    }
    
    var showNextVolumeSuggestion: Bool = false
    private(set) var nextComic: LocalComic?
    
    var isSpreadMode: Bool {
        return isSpreadEnabled && isLandscape
    }
    
    private let source: any ComicSource
    
    init(source: any ComicSource) {
        self.source = source
        self.currentPage = source.lastReadPage
        
        // 次の巻があるか事前にチェック
        Task {
            await checkForNextVolume()
        }
    }
    
    private func checkForNextVolume() async {
        guard let currentLocal = source as? LocalComicSource else { return }
        let currentTitle = currentLocal.title
        
        // 全てのコミックを取得
        guard let allComics = try? LocalStorageService.shared.loadComics() else { return }
        
        // 同じシリーズと思われるものを抽出してソート
        // 例: "漫画 第01巻", "漫画 第02巻" -> 接頭辞が一致するものを探す
        let prefix = currentTitle.prefix(max(5, currentTitle.count - 5))
        let seriesVolumes = allComics
            .filter { $0.title.hasPrefix(prefix) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        
        if let currentIndex = seriesVolumes.firstIndex(where: { $0.id == currentLocal.id }),
           currentIndex + 1 < seriesVolumes.count {
            self.nextComic = seriesVolumes[currentIndex + 1]
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
            
            if !isSpreadShifted {
                // 1ページ目（表紙）は単独
                indices.append(0)
                current = 1
            }
            
            while current < pageCount {
                indices.append(current)
                current += 2
            }
            return indices
        } else {
            return Array(0..<pageCount)
        }
    }
    
    /// 任意のページ番号を、現在の表示モードにおける有効な開始インデックスに変換する
    func normalizePageIndex(_ page: Int) -> Int {
        guard isSpreadMode else { return max(0, min(pageCount - 1, page)) }
        
        if !isSpreadShifted {
            if page <= 0 { return 0 }
            // 1, 2 -> 1 / 3, 4 -> 3 ... (奇数に丸める)
            return ((page - 1) / 2) * 2 + 1
        } else {
            // 0, 1 -> 0 / 2, 3 -> 2 ... (偶数に丸める)
            return (page / 2) * 2
        }
    }
    
    func goToNextPage() {
        if currentPage < pageCount - 1 {
            let currentIndex = pageIndices.firstIndex(of: currentPage) ?? 0
            let newIndex = min(pageIndices.count - 1, currentIndex + 1)
            let nextPageIndex = pageIndices[newIndex]
            
            // すでに最後のインデックスにいて、さらに次へ行こうとした場合
            if currentPage == nextPageIndex && nextComic != nil {
                showNextVolumeSuggestion = true
            } else {
                currentPage = nextPageIndex
            }
        } else if nextComic != nil {
            showNextVolumeSuggestion = true
        }
    }
    
    func goToPreviousPage() {
        if showNextVolumeSuggestion {
            showNextVolumeSuggestion = false
            return
        }
        
        if currentPage > 0 {
            let currentIndex = pageIndices.firstIndex(of: currentPage) ?? 0
            let newIndex = max(0, currentIndex - 1)
            currentPage = pageIndices[newIndex]
        }
    }
    
    /// 見開きページのインデックスを取得（左、右）
    func getSpreadIndices(for baseIndex: Int) -> (Int?, Int?) {
        if !isSpreadShifted && baseIndex == 0 {
            // シフトなしの場合、0ページ目は単独
            var left: Int?
            var right: Int?
            if isRightToLeft {
                left = nil
                right = 0
            } else {
                left = 0
                right = nil
            }
            if isSpreadSwapped {
                swap(&left, &right)
            }
            return (left, right)
        }
        
        let targetIndex = baseIndex
        let nextIndex = targetIndex + 1 < pageCount ? targetIndex + 1 : nil
        
        var left: Int?
        var right: Int?
        
        if isRightToLeft {
            // 日本の漫画（右開き）：若い数字が右、次の数字が左
            left = nextIndex
            right = targetIndex
        } else {
            // アメコミ等（左開き）：若い数字が左、次の数字が右
            left = targetIndex
            right = nextIndex
        }
        
        if isSpreadSwapped {
            swap(&left, &right)
        }
        
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
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
        }
        .task {
            // すでに読み込まれていればスキップ
            if image == nil {
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }
        
        // ソースから画像を取得（ダウンスプリング等はSource側でやる想定だが、念のため）
        // LocalComicSource等はすでにダウンサンプリング済みを返す
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
