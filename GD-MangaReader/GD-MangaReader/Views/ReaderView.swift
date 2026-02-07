// ReaderView.swift
// GD-MangaReader
//
// 漫画閲覧画面 - 横読み（RTL/LTR）、縦読み、ズーム、見開き表示対応

import SwiftUI

/// 漫画閲覧画面
struct ReaderView: View {
    let comic: LocalComic
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    init(comic: LocalComic) {
        self.comic = comic
        self._viewModel = State(initialValue: ReaderViewModel(comic: comic))
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
        }
        .ignoresSafeArea()
        .statusBarHidden(!viewModel.showUI)
        .onAppear {
            viewModel.updateSpreadMode(for: horizontalSizeClass)
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            viewModel.updateSpreadMode(for: newValue)
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
        .environment(\.layoutDirection, viewModel.isRightToLeft ? .rightToLeft : .leftToRight)
    }
    
    // MARK: - Vertical Reader (Scroll)
    
    @ViewBuilder
    private func verticalReader(geometry: GeometryProxy) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.pageRange, id: \.self) { index in
                        ZoomableImageView(
                            imagePath: comic.imagePaths[index],
                            geometry: geometry
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
            imagePath: comic.imagePaths[index],
            geometry: geometry
        )
    }
    
    // MARK: - Spread Page View (Two pages side by side)
    
    @ViewBuilder
    private func spreadPageView(index: Int, geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let (leftIndex, rightIndex) = viewModel.getSpreadIndices(for: index)
            
            if let leftIndex = leftIndex {
                ZoomableImageView(
                    imagePath: comic.imagePaths[leftIndex],
                    geometry: geometry,
                    isHalfWidth: true
                )
            } else {
                Color.black
                    .frame(width: geometry.size.width / 2)
            }
            
            if let rightIndex = rightIndex {
                ZoomableImageView(
                    imagePath: comic.imagePaths[rightIndex],
                    geometry: geometry,
                    isHalfWidth: true
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
            
            Spacer()
            
            // フッター
            footerBar
        }
        .transition(.opacity)
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
            
            Text(comic.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            settingsMenu
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
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
            if horizontalSizeClass == .regular {
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
                    in: 0...Double(max(0, comic.pageCount - 1)),
                    step: 1
                )
                .tint(.orange)
                .environment(\.layoutDirection, viewModel.isRightToLeft ? .rightToLeft : .leftToRight)
                
                Text("\(comic.pageCount)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 40)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
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
    
    // MARK: - Progress Save
    
    private func saveProgress() {
        Task {
            var updatedComic = comic
            updatedComic.lastReadPage = viewModel.currentPage
            updatedComic.lastReadAt = Date()
            try? await LocalStorageService.shared.updateComic(updatedComic)
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
    var isSpreadMode: Bool = false
    
    private let comic: LocalComic
    
    init(comic: LocalComic) {
        self.comic = comic
        self.currentPage = comic.lastReadPage
    }
    
    var pageCount: Int {
        comic.pageCount
    }
    
    var pageRange: Range<Int> {
        0..<pageCount
    }
    
    var pageIndices: [Int] {
        if isSpreadMode {
            // 見開きモード：2ページずつ
            return stride(from: 0, to: pageCount, by: 2).map { $0 }
        } else {
            return Array(0..<pageCount)
        }
    }
    
    func goToNextPage() {
        if currentPage < pageCount - 1 {
            currentPage += isSpreadMode ? 2 : 1
            currentPage = min(currentPage, pageCount - 1)
        }
    }
    
    func goToPreviousPage() {
        if currentPage > 0 {
            currentPage -= isSpreadMode ? 2 : 1
            currentPage = max(currentPage, 0)
        }
    }
    
    func updateSpreadMode(for sizeClass: UserInterfaceSizeClass?) {
        isSpreadMode = isSpreadEnabled && sizeClass == .regular
    }
    
    /// 見開きページのインデックスを取得（左、右）
    func getSpreadIndices(for baseIndex: Int) -> (Int?, Int?) {
        if isRightToLeft {
            // 右から左：右ページが先
            let rightIndex = baseIndex
            let leftIndex = baseIndex + 1 < pageCount ? baseIndex + 1 : nil
            return (leftIndex, rightIndex < pageCount ? rightIndex : nil)
        } else {
            // 左から右：左ページが先
            let leftIndex = baseIndex
            let rightIndex = baseIndex + 1 < pageCount ? baseIndex + 1 : nil
            return (leftIndex < pageCount ? leftIndex : nil, rightIndex)
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let imagePath: URL
    let geometry: GeometryProxy
    var isHalfWidth: Bool = false
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    
    var body: some View {
        let imageWidth = isHalfWidth ? geometry.size.width / 2 : geometry.size.width
        
        AsyncImageView(url: imagePath)
            .aspectRatio(contentMode: .fit)
            .frame(width: imageWidth, height: geometry.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture)
            .gesture(dragGesture)
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

// MARK: - Async Image View (Local File)

struct AsyncImageView: View {
    let url: URL
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
            await loadImage()
        }
    }
    
    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }
        
        // バックグラウンドで画像読み込み
        let loadedImage = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let uiImage = UIImage(data: data) else {
                return nil as UIImage?
            }
            // ダウンサンプリングでメモリ効率化
            return downsample(image: uiImage, to: UIScreen.main.bounds.size)
        }.value
        
        await MainActor.run {
            self.image = loadedImage
        }
    }
    
    /// 画像をダウンサンプリング
    private func downsample(image: UIImage, to targetSize: CGSize) -> UIImage {
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        if scale >= 1.0 {
            return image
        }
        
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

#Preview {
    ReaderView(comic: .mock)
}
