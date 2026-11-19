import Combine
import Foundation

@MainActor
final class SyncReceiver: ObservableObject {
    struct Review: Identifiable {
        let id = UUID()
        let overwrite: Bool
        let summary: String
    }

    @Published private(set) var review: Review?
    @Published private(set) var result: String?
    private var decision: CheckedContinuation<Bool, Never>?
    private var deadline: Task<Void, Never>?
    private var receiving = false
    private let importer: SyncImporter

    init(importer: SyncImporter) {
        self.importer = importer
    }

    func receive(_ profile: SyncProfile, selection: SyncSelection, overwrite: Bool,
                 reviewTimeout: Duration = .seconds(60)) async throws -> String {
        guard !receiving else { throw SyncError.busy }
        receiving = true
        defer { receiving = false }
        do {
            let plan = try profile.prepare(selection)
            if overwrite || plan.accounts != nil {
                let request = Review(overwrite: overwrite, summary: plan.summary)
                let approved = await waitForReview(request, timeout: reviewTimeout)
                guard approved else { throw SyncError.confirmationRequired }
            }
            try await importer.apply(plan, overwrite: overwrite, confirmed: true)
            result = "已导入 · \(plan.summary)"
            return plan.summary
        } catch {
            result = error is CancellationError ? "已取消导入" : error.localizedDescription
            throw error
        }
    }

    func answer(_ approved: Bool, id: UUID? = nil) {
        guard let review, id == nil || review.id == id else { return }
        self.review = nil
        deadline?.cancel()
        deadline = nil
        decision?.resume(returning: approved)
        decision = nil
    }

    private func waitForReview(_ request: Review, timeout: Duration) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { return continuation.resume(returning: false) }
                decision = continuation
                review = request
                deadline = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        self?.answer(false, id: request.id)
                    } catch {}
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.answer(false, id: request.id) }
        }
    }
}
