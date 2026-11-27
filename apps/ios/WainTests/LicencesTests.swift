import XCTest
@testable import Wain

final class LicencesTests: XCTestCase {
    /// Every package and bundled script project.yml ships has an entry, and every entry's licence has its text.
    func testEveryShippedPartHasItsLicence() throws {
        let l = Licences.shared
        XCTAssertFalse(l.components.isEmpty, "licences.json did not load")
        for c in l.components { XCTAssertNotNil(l.licences[c.licence], "\(c.name): no \(c.licence) text") }

        let covered = Set(l.components.flatMap(\.covers))
        let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let spec = try String(contentsOf: ios.appendingPathComponent("project.yml"), encoding: .utf8)
        // A package is a two-space key under `packages:`; deeper lines are its url and revision.
        let packages = try XCTUnwrap(spec.components(separatedBy: "\npackages:\n").last)
            .components(separatedBy: "\n")
            .prefix { $0.hasPrefix("  ") }
            .filter { !$0.hasPrefix("   ") }
            .map { String($0.trimmingCharacters(in: .whitespaces).dropLast()) }
        XCTAssertFalse(packages.isEmpty)
        let scripts = try FileManager.default.contentsOfDirectory(atPath: ios.appendingPathComponent("Wain").path)
            .filter { $0.hasSuffix(".js") } + (spec.contains("botface.js") ? ["botface.js"] : [])
        for name in packages + scripts {
            XCTAssertTrue(covered.contains(name), "\(name) ships with no entry in licences.json")
        }
    }
}
