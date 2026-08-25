import XCTest
@testable import Glance

final class WindowDetectorTests: XCTestCase {
    func test_coordinateConversion_symmetry() {
        let primaryHeight: CGFloat = 1080.0
        let originalAppKitRect = CGRect(x: 100, y: 200, width: 800, height: 600)

        let cgRect = CaptureGeometry.cgRect(fromAppKitRect: originalAppKitRect, primaryScreenHeight: primaryHeight)
        let roundtripAppKitRect = CaptureGeometry.appKitRect(fromCGRect: cgRect, primaryScreenHeight: primaryHeight)

        XCTAssertEqual(originalAppKitRect.origin.x, roundtripAppKitRect.origin.x, accuracy: 0.001)
        XCTAssertEqual(originalAppKitRect.origin.y, roundtripAppKitRect.origin.y, accuracy: 0.001)
        XCTAssertEqual(originalAppKitRect.width, roundtripAppKitRect.width, accuracy: 0.001)
        XCTAssertEqual(originalAppKitRect.height, roundtripAppKitRect.height, accuracy: 0.001)
    }

    func test_findWindow_returnsTopmostWindowInZOrder() {
        let detector = WindowDetector()

        let frontWindow = DetectedWindow(
            id: 101,
            ownerName: "Safari",
            windowName: "GitHub - Pull Request #3",
            bounds: CGRect(x: 100, y: 100, width: 500, height: 400),
            layer: 0,
            alpha: 1.0,
            ownerPID: 1001
        )

        let backWindow = DetectedWindow(
            id: 102,
            ownerName: "Xcode",
            windowName: "Glance.xcodeproj",
            bounds: CGRect(x: 200, y: 200, width: 600, height: 500),
            layer: 0,
            alpha: 1.0,
            ownerPID: 1002
        )

        let candidateWindows = [frontWindow, backWindow]

        // Point inside both windows: (300, 300)
        let hitBoth = detector.findWindow(at: CGPoint(x: 300, y: 300), in: candidateWindows)
        XCTAssertEqual(hitBoth?.id, 101, "Frontmost window in array must take precedence")

        // Point inside only back window: (650, 600)
        let hitBackOnly = detector.findWindow(at: CGPoint(x: 650, y: 600), in: candidateWindows)
        XCTAssertEqual(hitBackOnly?.id, 102)

        // Point outside all windows: (10, 10)
        let hitNone = detector.findWindow(at: CGPoint(x: 10, y: 10), in: candidateWindows)
        XCTAssertNil(hitNone)
    }

    func test_detectedWindow_displayTag() {
        let namedWindow = DetectedWindow(
            id: 1,
            ownerName: "Safari",
            windowName: "Apple Developer",
            bounds: .zero,
            layer: 0,
            alpha: 1.0,
            ownerPID: 100
        )
        XCTAssertEqual(namedWindow.displayTag, "Safari — Apple Developer")

        let unnamedWindow = DetectedWindow(
            id: 2,
            ownerName: "Finder",
            windowName: nil,
            bounds: .zero,
            layer: 0,
            alpha: 1.0,
            ownerPID: 200
        )
        XCTAssertEqual(unnamedWindow.displayTag, "Finder")

        let duplicateNamedWindow = DetectedWindow(
            id: 3,
            ownerName: "Terminal",
            windowName: "Terminal",
            bounds: .zero,
            layer: 0,
            alpha: 1.0,
            ownerPID: 300
        )
        XCTAssertEqual(duplicateNamedWindow.displayTag, "Terminal")
    }
}
