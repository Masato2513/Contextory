import XCTest
@testable import ContextoryCore

final class MemoryOptimizationTests: XCTestCase {
    func testConsumerWaitsForAsyncCompletionAndDrainsWithoutFurtherSignals() throws {
        let storage = try TestStorage.make()
        defer { try? TestStorage.removeIfPresent(storage.root) }
        let submissions = (0..<5).map { expectation(description: "提交动作 \($0)") }
        let action = DeferredMemoryProbe { index in submissions[index].fulfill() }
        let dispatcher = ActionDispatcher()
        dispatcher.register(action: action)
        for _ in 0..<5 {
            try storage.manager.enqueueAction(actionId: action.actionId, paths: [storage.root.path])
        }
        let consumer = PendingActionConsumer(storage: storage.manager, dispatcher: dispatcher, batchSize: 2)
        defer { consumer.stop() }
        DispatchQueue.concurrentPerform(iterations: 100) { _ in consumer.signal() }

        for index in 0..<5 {
            wait(for: [submissions[index]], timeout: 5)
            if index == 0 {
                // 一个异步动作等待用户输入时，其余批次必须仍留在磁盘。
                XCTAssertEqual(storage.manager.pendingActionCount, 3)
            }
            action.finishCurrent()
        }
        XCTAssertEqual(storage.manager.pendingActionCount, 0)
        let inFlight = try FileManager.default.subpathsOfDirectory(atPath: storage.manager.inFlightActionsDirectoryURL.path)
        XCTAssertFalse(inFlight.contains { $0.hasSuffix(".json") })
    }

    func testExtensionDescriptorsMatchHostActions() {
        let actions = DefaultActionRegistry.makeActions()
        XCTAssertEqual(FileActionDescriptor.all.map(\.actionId), actions.map(\.actionId))
        XCTAssertEqual(FileActionDescriptor.all.map(\.localizedTitle), actions.map(\.localizedTitle))
        XCTAssertEqual(FileActionDescriptor.all.map { Optional($0.iconName) }, actions.map(\.iconName))
        XCTAssertEqual(Set(FileActionDescriptor.all.map(\.actionId)).count, 8)
    }

    func testBatchesLeaveUnclaimedEventsOnDiskAndDrainWithoutDuplicates() throws {
        let storage = try TestStorage.make()
        defer { try? TestStorage.removeIfPresent(storage.root) }
        for index in 0..<75 {
            try storage.manager.enqueueAction(actionId: "batch.\(index)", paths: ["/tmp/\(index)"])
        }

        var received: [String] = []
        for expectedCount in [32, 32, 11] {
            let leases = storage.manager.consumePendingActionLeases(limit: 32)
            XCTAssertEqual(leases.count, expectedCount)
            received += leases.map(\.event.actionId)
            XCTAssertEqual(storage.manager.pendingActionCount, 75 - received.count)
            XCTAssertTrue(leases.allSatisfy {
                $0.inFlightURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
            })
            leases.forEach { storage.manager.acknowledge($0) }
        }
        XCTAssertEqual(Set(received), Set((0..<75).map { "batch.\($0)" }))
        XCTAssertTrue(storage.manager.consumePendingActionLeases(limit: 32).isEmpty)
    }

    func testCorruptFilesAndLegacyEventDoNotBreakBatchLimit() throws {
        let storage = try TestStorage.make()
        defer { try? TestStorage.removeIfPresent(storage.root) }
        let manager = storage.manager
        try Data("broken".utf8).write(to: manager.pendingActionsDirectoryURL.appendingPathComponent("broken.json"))
        try manager.enqueueAction(actionId: "modern", paths: ["/tmp/modern"])
        try JSONSerialization.data(withJSONObject: ["actionId": "legacy", "paths": ["/tmp/legacy"]])
            .write(to: manager.pendingActionURL)

        XCTAssertTrue(manager.consumePendingActionLeases(limit: 0).isEmpty)
        XCTAssertEqual(manager.pendingActionCount, 2)
        let first = manager.consumePendingActionLeases(limit: 1)
        XCTAssertEqual(first.map(\.event.actionId), ["modern"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.pendingActionURL.path))
        first.forEach { manager.acknowledge($0) }

        let second = manager.consumePendingActionLeases(limit: 1)
        XCTAssertEqual(second.map(\.event.actionId), ["legacy"])
        XCTAssertEqual(manager.failedActionCount, 1)
        XCTAssertTrue(manager.consumePendingActionLeases(limit: 1).isEmpty)
    }
}

private final class DeferredMemoryProbe: MenuAction, @unchecked Sendable {
    let actionId = "memory.deferred"
    let localizedTitle = "内存验证动作"
    let iconName: String? = nil
    private let lock = NSLock()
    private var count = 0
    private var completion: (@Sendable (ActionCompletionStatus) -> Void)?
    private let didSubmit: @Sendable (Int) -> Void

    init(didSubmit: @escaping @Sendable (Int) -> Void) {
        self.didSubmit = didSubmit
    }

    func execute(targetURLs: [URL]) -> Bool { false }

    func submit(targetURLs: [URL], completion: @escaping @Sendable (ActionCompletionStatus) -> Void) -> ActionSubmission {
        lock.lock()
        // 若消费器错误地并发提交，测试会在这里直接发现覆盖尚未完成的动作。
        XCTAssertNil(self.completion)
        self.completion = completion
        let index = count
        count += 1
        lock.unlock()
        didSubmit(index)
        return .accepted
    }

    func finishCurrent() {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(.succeeded)
    }
}
