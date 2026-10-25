import XCTest
@testable import FitnessCore

/// Scenarios from muscle-anatomy.feature about the catalog the figure and editor are built on.
final class MuscleCatalogTests: XCTestCase {
    func testCatalogHas33PartsIn14Regions() {
        XCTAssertEqual(MusclePart.allCases.count, 33)
        XCTAssertEqual(MuscleRegion.allCases.count, 14)
    }

    func testEveryPartBelongsToExactlyOneRegionAndEveryRegionHasParts() {
        for region in MuscleRegion.allCases {
            XCTAssertFalse(region.parts.isEmpty, "\(region) has no parts")
        }
        let listed = MuscleRegion.allCases.flatMap(\.parts)
        XCTAssertEqual(listed.count, MusclePart.allCases.count)
        XCTAssertEqual(Set(listed), Set(MusclePart.allCases))
    }

    func testRegionsListTheirPartsInBodyOrder() {
        XCTAssertEqual(MuscleRegion.chest.parts, [.chestUpper, .chestMid, .chestLower])
        XCTAssertEqual(MuscleRegion.upperBack.parts, [.trapsUpper, .trapsMid, .trapsLower, .lats, .rhomboids, .teres])
        XCTAssertEqual(MuscleRegion.triceps.parts, [.tricepsLong, .tricepsLateral])
    }

    func testReadableNames() {
        XCTAssertEqual(MusclePart.chestUpper.displayName, "Upper chest")
        XCTAssertEqual(MusclePart.teres.displayName, "Teres and rotator cuff")
        XCTAssertEqual(MusclePart.tricepsLong.displayName, "Triceps long head")
        XCTAssertEqual(MuscleRegion.upperBack.displayName, "Upper back")
        XCTAssertEqual(MusclePart.gluteMax.displayName, "Glute max")
    }

    func testPartsKeepStableStorageKeys() {
        XCTAssertEqual(MusclePart.chestUpper.rawValue, "chest_upper")
        XCTAssertEqual(MusclePart.hamOuter.rawValue, "ham_outer")
        XCTAssertEqual(Set(MusclePart.allCases.map(\.rawValue)).count, 33, "keys are unique")
    }

    func testVisibleViewsMatchTheDrawnFigure() {
        for part in MusclePart.allCases {
            let drawnFront = MuscleFigureData.front[part.rawValue] != nil
            let drawnBack = MuscleFigureData.back[part.rawValue] != nil
            XCTAssertTrue(drawnFront || drawnBack, "\(part) is not drawn in any view")
            XCTAssertEqual(part.views.contains(.front), drawnFront, "\(part) front")
            XCTAssertEqual(part.views.contains(.back), drawnBack, "\(part) back")
        }
    }

    func testEverythingDrawnIsInTheCatalog() {
        let catalog = Set(MusclePart.allCases.map(\.rawValue))
        XCTAssertTrue(Set(MuscleFigureData.front.keys).isSubset(of: catalog))
        XCTAssertTrue(Set(MuscleFigureData.back.keys).isSubset(of: catalog))
    }

    func testPartsVisibleFromBothSides() {
        for part in [MusclePart.deltSide, .trapsUpper, .abductors, .gastrocnemius] {
            XCTAssertEqual(part.views, [.front, .back], "\(part)")
        }
        XCTAssertEqual(MusclePart.tricepsLong.views, [.back])
        XCTAssertEqual(MusclePart.chestUpper.views, [.front])
    }

    func testShapesArePathDataThatTheAppCanDraw() {
        let allShapes = Array(MuscleFigureData.front.values) + Array(MuscleFigureData.back.values) + [MuscleFigureData.base]
        for paths in allShapes {
            for path in paths {
                XCTAssertTrue(path.hasPrefix("M "), path)
                XCTAssertTrue(path.hasSuffix(" Z"), path)
            }
        }
    }
}
