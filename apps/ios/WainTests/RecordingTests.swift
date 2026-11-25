import XCTest
@testable import Wain

final class RecordingTests: XCTestCase {
    func testFindsRecordingsInAnyHomeOnceEach() {
        let text = """
        Watch /Users/me/.wain/browser/recordings/s1/flow.mp4 and
        [the other](/srv/wain/browser/recordings/s1/screen.mp4), then
        /Users/me/.wain/browser/recordings/s1/flow.mp4 again.
        """
        XCTAssertEqual(recordingPaths(in: text), [
            "/Users/me/.wain/browser/recordings/s1/flow.mp4",
            "/srv/wain/browser/recordings/s1/screen.mp4",
        ])
    }

    func testIgnoresWhatIsNotAnAbsoluteRecording() {
        XCTAssertEqual(recordingPaths(in: "see ~/.wain/browser/recordings/s1/a.mp4"), [])
        XCTAssertEqual(recordingPaths(in: "/Users/me/wain-test-videos/a.mp4"), [])
        XCTAssertEqual(recordingPaths(in: "/x/browser/recordings/s1/a.mov"), [])
    }

    func testFindsImagesApartFromRecordings() {
        let text = "Before /srv/wain/browser/recordings/s1/before.png, after (/srv/wain/browser/recordings/s1/after.jpg) and /srv/wain/browser/recordings/s1/flow.mp4"
        XCTAssertEqual(imagePaths(in: text), [
            "/srv/wain/browser/recordings/s1/before.png",
            "/srv/wain/browser/recordings/s1/after.jpg",
        ])
        XCTAssertEqual(recordingPaths(in: text), ["/srv/wain/browser/recordings/s1/flow.mp4"])
        XCTAssertEqual(imagePaths(in: "Saved `/Users/me/Desktop/Shot.PNG`."), ["/Users/me/Desktop/Shot.PNG"])
    }

    func testIgnoresImagePathsInCodeAndUrls() {
        XCTAssertEqual(imagePaths(in: "```\ncp a.png /tmp/b.png\n```"), [])
        XCTAssertEqual(imagePaths(in: "https://example.com/a.png and /tmp/a.png.bak"), [])
    }

    func testLeavesAnImageWrittenAsAMarkdownLineToItsBlock() {
        let text = "Done.\n\n![After](/srv/wain/browser/recordings/s1/after.png)\n\nAlso /srv/wain/browser/recordings/s1/before.png"
        XCTAssertEqual(imagePaths(in: text), ["/srv/wain/browser/recordings/s1/before.png"])
    }

    func testHidesDrawnPathsFromTheText() {
        let video = "/Users/me/.wain/browser/recordings/s1/flow.mp4"
        let shot = "/tmp/shot.png"
        let text = """
        Recorded it: `\(video)`
        \(shot)
        Saved to \(shot).
        Outside: `\(shot)`.
        See [the shot](\(shot)) and ![x](\(shot)) here.
        ![Block](\(shot))
        ```
        open \(shot)
        ```
        """
        XCTAssertEqual(hiding([video, shot], in: text), """
        Recorded it:
        Saved to.
        Outside:
        See and here.
        ![Block](\(shot))
        ```
        open \(shot)
        ```
        """)
    }

    func testLeavesACommandInACodeSpanWhole() {
        let text = "Run `open /tmp/a.png -a Preview` to see /tmp/a.png."
        XCTAssertEqual(hiding(["/tmp/a.png"], in: text), "Run `open /tmp/a.png -a Preview` to see.")
    }

    func testHidesOnlyWholePaths() {
        let text = "Shot /tmp/a.png, backup [old](/tmp/a.png.bak) and /tmp/a.png.bak"
        XCTAssertEqual(hiding(["/tmp/a.png"], in: text), "Shot, backup [old](/tmp/a.png.bak) and /tmp/a.png.bak")
    }
}
