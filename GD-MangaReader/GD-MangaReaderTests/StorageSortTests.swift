import XCTest
@testable import GD_MangaReader

/// `StorageViewModel.sortOption`（および内部の`sortComics`）の並び替えを検証する。
///
/// `StorageViewModel`は`LocalStorageService.shared`（シングルトン、DI不可）に直接依存し、
/// `comics`は`private(set)`・`sortComics`は`private`のため、外部からアイテムを直接注入する
/// 手段がない。そのため`LocalComicSourceTests`と同様に、実ファイルシステム上に
/// テスト用のコミックディレクトリとメタデータを作成し、`loadData()`を通して検証する。
/// メタデータファイルは既存内容を退避し、テスト終了時に必ず復元する。
@MainActor
final class StorageSortTests: XCTestCase {

    private let storageService = LocalStorageService.shared
    private var originalComics: [LocalComic] = []
    private var createdDirectoryNames: [String] = []

    // テスト用コミック（サイズ・名前・日付がそれぞれ異なる順序になるよう設計）
    // - サイズ降順: Charlie(300) > Bravo(200) > Alpha(100)
    // - 名前昇順:   Alpha < Bravo < Charlie
    // - 追加日降順: Alpha(day2) > Bravo(day1) > Charlie(day0)
    private var alphaComic: LocalComic!
    private var bravoComic: LocalComic!
    private var charlieComic: LocalComic!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // バックアップ取得に失敗した場合はテストを失敗させる
        // （try?で[]に潰すと、tearDownが実カタログを空配列で上書きしてしまう）
        originalComics = try storageService.loadComics()
        createdDirectoryNames = []

        let day0 = Date(timeIntervalSince1970: 1_000_000)
        let day1 = Date(timeIntervalSince1970: 1_100_000)
        let day2 = Date(timeIntervalSince1970: 1_200_000)

        alphaComic = try makeComic(title: "Alpha", byteCount: 100, downloadedAt: day2)
        bravoComic = try makeComic(title: "Bravo", byteCount: 200, downloadedAt: day1)
        charlieComic = try makeComic(title: "Charlie", byteCount: 300, downloadedAt: day0)

        // メタデータを今回のテスト用3件のみに差し替える（tearDownで必ず復元）
        try storageService.saveComics([alphaComic, bravoComic, charlieComic])
    }

    override func tearDownWithError() throws {
        for name in createdDirectoryNames {
            let dir = storageService.comicsDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        // 復元失敗はデータ破壊なので握り潰さずテストを失敗させる
        try storageService.saveComics(originalComics)

        alphaComic = nil
        bravoComic = nil
        charlieComic = nil
        originalComics = []
        createdDirectoryNames = []

        try super.tearDownWithError()
    }

    /// 指定バイト数のダミーファイルを1つ持つコミック用ディレクトリを実際に作成し、
    /// 対応する`LocalComic`を返す。
    private func makeComic(title: String, byteCount: Int, downloadedAt: Date) throws -> LocalComic {
        let dirName = "StorageSortTests_\(title)_\(UUID().uuidString)"
        let dirURL = storageService.comicsDirectory.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        createdDirectoryNames.append(dirName)

        let fileURL = dirURL.appendingPathComponent("page1.dat")
        let data = Data(repeating: 0, count: byteCount)
        try data.write(to: fileURL)

        return LocalComic(
            title: title,
            driveFileId: "drive-\(dirName)",
            localPath: dirName,
            imageFileNames: ["page1.dat"],
            downloadedAt: downloadedAt,
            status: .completed
        )
    }

    private func loadedTitles(_ viewModel: StorageViewModel) -> [String] {
        viewModel.comics.map(\.title)
    }

    // MARK: - Default: size descending

    func testLoadData_DefaultSortOption_IsSizeDesc() async {
        let viewModel = StorageViewModel()

        XCTAssertEqual(viewModel.sortOption, .sizeDesc)

        await viewModel.loadData()

        XCTAssertEqual(loadedTitles(viewModel), ["Charlie", "Bravo", "Alpha"])
    }

    // MARK: - Name ascending

    func testSortOption_NameAsc_OrdersAlphabetically() async {
        let viewModel = StorageViewModel()
        await viewModel.loadData()

        viewModel.sortOption = .nameAsc

        XCTAssertEqual(loadedTitles(viewModel), ["Alpha", "Bravo", "Charlie"])
    }

    // MARK: - Date newest first

    func testSortOption_DateNewest_OrdersByDownloadedAtDescending() async {
        let viewModel = StorageViewModel()
        await viewModel.loadData()

        viewModel.sortOption = .dateNewest

        // Alpha has the most recent downloadedAt (day2), Charlie the oldest (day0)
        XCTAssertEqual(loadedTitles(viewModel), ["Alpha", "Bravo", "Charlie"])
    }

    // MARK: - Switching back re-sorts using the new option, not a stale order

    func testSortOption_SwitchingBetweenOptions_AlwaysReflectsCurrentOption() async {
        let viewModel = StorageViewModel()
        await viewModel.loadData()

        viewModel.sortOption = .nameAsc
        XCTAssertEqual(loadedTitles(viewModel), ["Alpha", "Bravo", "Charlie"])

        viewModel.sortOption = .sizeDesc
        XCTAssertEqual(loadedTitles(viewModel), ["Charlie", "Bravo", "Alpha"])

        viewModel.sortOption = .dateNewest
        XCTAssertEqual(loadedTitles(viewModel), ["Alpha", "Bravo", "Charlie"])
    }

    // MARK: - Sizes are computed correctly for the size sort

    func testLoadData_ComputesActualFileSizesFromDisk() async {
        let viewModel = StorageViewModel()
        await viewModel.loadData()

        let sizesByTitle = Dictionary(uniqueKeysWithValues: viewModel.comics.map { ($0.title, $0.size) })
        XCTAssertEqual(sizesByTitle["Alpha"], 100)
        XCTAssertEqual(sizesByTitle["Bravo"], 200)
        XCTAssertEqual(sizesByTitle["Charlie"], 300)
    }
}
