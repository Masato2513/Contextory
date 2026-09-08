import XCTest
@testable import ContextoryCore

final class LaunchPresentationPolicyTests: XCTestCase {
    func testOrdinaryUserLaunchAlwaysShowsSettings() {
        XCTAssertTrue(
            LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
                silentLaunchEnabled: true,
                arguments: [],
                launchedAsLoginItem: false
            )
        )
    }

    func testFinderExtensionRecoveryNeverShowsSettings() {
        XCTAssertFalse(
            LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
                silentLaunchEnabled: false,
                arguments: [LaunchPresentationPolicy.backgroundLaunchArgument],
                launchedAsLoginItem: false
            )
        )
    }

    func testSilentLoginLaunchStaysHidden() {
        XCTAssertFalse(
            LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
                silentLaunchEnabled: true,
                arguments: [],
                launchedAsLoginItem: true
            )
        )
    }

    func testNonSilentLoginLaunchShowsSettings() {
        XCTAssertTrue(
            LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
                silentLaunchEnabled: false,
                arguments: [],
                launchedAsLoginItem: true
            )
        )
    }

    func testExplicitQuitTreatsFinderAndLoginLaunchesAsBackground() {
        XCTAssertTrue(
            LaunchPresentationPolicy.isBackgroundRequest(
                arguments: [LaunchPresentationPolicy.backgroundLaunchArgument],
                launchedAsLoginItem: false
            )
        )
        XCTAssertTrue(
            LaunchPresentationPolicy.isBackgroundRequest(
                arguments: [],
                launchedAsLoginItem: true
            )
        )
        XCTAssertFalse(
            LaunchPresentationPolicy.isBackgroundRequest(
                arguments: [],
                launchedAsLoginItem: false
            )
        )
    }
}
