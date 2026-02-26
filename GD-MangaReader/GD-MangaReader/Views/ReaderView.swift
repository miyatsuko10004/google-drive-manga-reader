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
                saveProgress()
                dismiss()
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
                        set: { viewModel.currentPage = Int($0) }
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
    
    private func saveProgress() {
        Task {
            await source.saveProgress(page: viewModel.currentPage)
        }
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
    var isSpreadEnabled: Bool = true
    var isLandscape: Bool = false
    
    var isSpreadMode: Bool {
        return isSpreadEnabled && isLandscape
    }
    
    private let source: any ComicSource
    
    init(source: any ComicSource) {
        self.source = source
        self.currentPage = source.lastReadPage
    }
    
    var pageCount: Int {
        source.pageCount
    }
    
    var pageRange: Range<Int> {
        0..<pageCount
    }
    
    var pageIndices: [Int] {
        if isSpreadMode {
            // 見開きモード：表紙（インデックス0）は単独、以降2ページずつ
            var indices: [Int] = [0]
            var current = 1
            while current < pageCount {
                indices.append(current)
                current += 2
            }
            return indices
        } else {
            return Array(0..<pageCount)
        }
    }
    
    func goToNextPage() {
        if currentPage < pageCount - 1 {
            let currentIndex = pageIndices.firstIndex(of: currentPage) ?? 0
            let newIndex = min(pageIndices.count - 1, currentIndex + 1)
            currentPage = pageIndices[newIndex]
        }
    }
    
    func goToPreviousPage() {
        if currentPage > 0 {
            let currentIndex = pageIndices.firstIndex(of: currentPage) ?? 0
            let newIndex = max(0, currentIndex - 1)
            currentPage = pageIndices[newIndex]
        }
    }
    
    /// 見開きページのインデックスを取得（左、右）
    func getSpreadIndices(for baseIndex: Int) -> (Int?, Int?) {
        // 表紙（0）は常に単独で中央（右側に配置して左を空けるなど実装依存）
        if baseIndex == 0 {
            return (nil, 0)
        }
        
        let targetIndex = baseIndex
        let nextIndex = targetIndex + 1 < pageCount ? targetIndex + 1 : nil
        
        if isRightToLeft {
            // 日本の漫画（右開き）：若い数字が右、次の数字が左
            return (nextIndex, targetIndex)
        } else {
            // アメコミ等（左開き）：若い数字が左、次の数字が右
            return (targetIndex, nextIndex)
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let source: any ComicSource
    let index: Int
    let geometry: GeometryProxy
    var isHalfWidth: Bool = false
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
            .frame(width: imageWidth, height: geometry.size.height)
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
