import XCTest
@testable import GD_MangaReader

@MainActor
final class LibraryViewModelPersistenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LibraryViewModelPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults when empty

    func testInit_WithEmptyDefaults_UsesDefaultSortOptionAndViewMode() {
        // Arrange / Act
        let viewModel = LibraryViewModel(userDefaults: defaults)

        // Assert
        XCTAssertEqual(viewModel.sortOption, .nameAsc)
        XCTAssertEqual(viewModel.viewMode, .grid)
    }

    // MARK: - Persistence round trip via a second instance

    func testSettingSortOption_PersistsAcrossNewInstance() {
        // Arrange
        let first = LibraryViewModel(userDefaults: defaults)

        // Act
        first.sortOption = .dateNewest

        // Assert
        XCTAssertEqual(defaults.string(forKey: LibraryViewModel.sortOptionDefaultsKey), "dateNewest")
        let second = LibraryViewModel(userDefaults: defaults)
        XCTAssertEqual(second.sortOption, .dateNewest)
    }

    func testSettingViewMode_PersistsAcrossNewInstance() {
        // Arrange
        let first = LibraryViewModel(userDefaults: defaults)

        // Act
        first.viewMode = .list

        // Assert
        XCTAssertEqual(defaults.string(forKey: LibraryViewModel.viewModeDefaultsKey), "list")
        let second = LibraryViewModel(userDefaults: defaults)
        XCTAssertEqual(second.viewMode, .list)
    }

    // MARK: - Invalid stored values fall back to defaults

    func testInit_WithInvalidStoredSortOption_FallsBackToNameAsc() {
        // Arrange
        defaults.set("not-a-real-sort-option", forKey: LibraryViewModel.sortOptionDefaultsKey)

        // Act
        let viewModel = LibraryViewModel(userDefaults: defaults)

        // Assert
        XCTAssertEqual(viewModel.sortOption, .nameAsc)
    }

    func testInit_WithInvalidStoredViewMode_FallsBackToGrid() {
        // Arrange
        defaults.set("carousel", forKey: LibraryViewModel.viewModeDefaultsKey)

        // Act
        let viewModel = LibraryViewModel(userDefaults: defaults)

        // Assert
        XCTAssertEqual(viewModel.viewMode, .grid)
    }

    // MARK: - Each raw value round-trips

    func testSortOption_AllCasesRoundTrip() {
        for option in LibraryViewModel.SortOption.allCases {
            // Arrange: fresh suite per case to avoid cross-contamination
            let caseSuite = "\(suiteName!).sort.\(option.rawValue)"
            let caseDefaults = UserDefaults(suiteName: caseSuite)!
            defer { caseDefaults.removePersistentDomain(forName: caseSuite) }

            let first = LibraryViewModel(userDefaults: caseDefaults)

            // Act
            first.sortOption = option

            // Assert
            let second = LibraryViewModel(userDefaults: caseDefaults)
            XCTAssertEqual(second.sortOption, option, "SortOption \(option.rawValue) failed to round-trip")
        }
    }

    func testViewMode_AllCasesRoundTrip() {
        for mode in LibraryViewModel.ViewMode.allCases {
            // Arrange: fresh suite per case to avoid cross-contamination
            let caseSuite = "\(suiteName!).viewmode.\(mode.rawValue)"
            let caseDefaults = UserDefaults(suiteName: caseSuite)!
            defer { caseDefaults.removePersistentDomain(forName: caseSuite) }

            let first = LibraryViewModel(userDefaults: caseDefaults)

            // Act
            first.viewMode = mode

            // Assert
            let second = LibraryViewModel(userDefaults: caseDefaults)
            XCTAssertEqual(second.viewMode, mode, "ViewMode \(mode.rawValue) failed to round-trip")
        }
    }
}
