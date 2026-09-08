import XCTest
@testable import ContextoryCore

final class FinderExtensionDiagnosticsTests: XCTestCase {
    func testPluginKitPlusPrefixMeansEnabled() {
        let output = "+    io.github.masato2513.Contextory.Extension(1.0.1)"

        XCTAssertEqual(
            FinderExtensionDiagnostics.registrationState(
                pluginKitOutput: output,
                commandSucceeded: true
            ),
            .enabled
        )
    }

    func testMissingPluginKitEntryMeansNotRegistered() {
        XCTAssertEqual(
            FinderExtensionDiagnostics.registrationState(
                pluginKitOutput: "",
                commandSucceeded: true
            ),
            .notRegistered
        )
    }

    func testEnabledExtensionWithRecentHeartbeatIsHealthy() {
        let snapshot = makeSnapshot(
            pluginKitState: .enabled,
            heartbeatState: .recent(observedPathCount: 1)
        )

        XCTAssertEqual(snapshot.menuServiceLevel, .healthy)
        XCTAssertEqual(snapshot.recommendedRepairAction, .none)
    }

    func testDisabledExtensionRequiresRegistration() {
        let snapshot = makeSnapshot(
            pluginKitState: .registeredButNotEnabled,
            heartbeatState: .recent(observedPathCount: 1)
        )

        XCTAssertEqual(snapshot.menuServiceLevel, .unavailable)
        XCTAssertEqual(snapshot.recommendedRepairAction, .registerExtension)
    }

    func testEnabledExtensionWithStaleHeartbeatRequiresFinderRestart() {
        let snapshot = makeSnapshot(
            pluginKitState: .enabled,
            heartbeatState: .stale
        )

        XCTAssertEqual(snapshot.menuServiceLevel, .unverified)
        XCTAssertEqual(snapshot.recommendedRepairAction, .restartFinder)
    }

    private func makeSnapshot(
        pluginKitState: FinderExtensionRegistrationState,
        heartbeatState: ExtensionHeartbeatState
    ) -> RightClickMenuHealthSnapshot {
        FinderExtensionDiagnostics.makeSnapshot(
            fullDiskAccessGranted: true,
            pluginKitState: pluginKitState,
            heartbeatState: heartbeatState,
            watchScope: .everywhere,
            pendingActionCount: 0,
            oldestPendingAge: nil,
            failedActionCount: 0
        )
    }
}
