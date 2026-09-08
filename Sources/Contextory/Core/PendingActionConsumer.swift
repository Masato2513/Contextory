import Foundation

/// 可从任意线程唤醒；所有消费状态仅在私有串行队列上读写。
/// 每批领取有限租约，异步动作到达终态后才推进下一项。
public final class PendingActionConsumer: @unchecked Sendable {
    private let storage: SharedStorageManager
    private let dispatcher: ActionDispatcher
    private let batchSize: Int
    private let queue: DispatchQueue
    private let source: DispatchSourceUserDataAdd
    private var pendingLeases: [PendingActionLease] = []
    private var isActionInFlight = false

    public init(
        storage: SharedStorageManager = .shared,
        dispatcher: ActionDispatcher = .shared,
        batchSize: Int = 32
    ) {
        precondition(batchSize > 0)
        self.storage = storage
        self.dispatcher = dispatcher
        self.batchSize = batchSize
        queue = DispatchQueue(
            label: "io.github.masato2513.Contextory.pending-dispatch",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem
        )
        source = DispatchSource.makeUserDataAddSource(queue: queue)
        source.setEventHandler { [weak self] in
            autoreleasepool { self?.drainNextAction() }
        }
        source.resume()
    }

    deinit { source.cancel() }

    /// 合并通知和目录变化，连续动作不会堆积大量空消费任务。
    public func signal() { source.add(data: 1) }

    public func stop() { source.cancel() }

    private func drainNextAction() {
        guard !source.isCancelled, !isActionInFlight else { return }
        if pendingLeases.isEmpty {
            pendingLeases = storage.consumePendingActionLeases(limit: batchSize).reversed()
        }
        guard let lease = pendingLeases.popLast() else { return }
        isActionInFlight = true
        let event = lease.event
        dispatcher.submit(
            actionId: event.actionId,
            targetURLs: event.paths.map { URL(fileURLWithPath: $0) },
            invocationKind: event.invocationKind
        ) { [storage, weak self] status in
            storage.writeLog("[App] 动作 \(event.actionId) 完成：\(String(describing: status))")
            storage.acknowledge(lease)
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.isActionInFlight = false
                self.signal()
            }
        }
    }
}
