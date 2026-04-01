import Foundation
import OSLog

struct PerformanceTrace {
    // Temporary debug instrumentation. Set to true when measuring account-switch performance again.
    private static let isEnabled = false
    private static let logger = Logger(
        subsystem: "net.bajancsalad.zse",
        category: "Performance"
    )

    private let clock = ContinuousClock()
    private let startedAt: ContinuousClock.Instant
    private let name: String
    private let context: String?
    private let identifier: String

    init(name: String, context: String? = nil) {
        self.startedAt = clock.now
        self.name = name
        self.context = context
        self.identifier = String(UUID().uuidString.prefix(8))
        log(stage: "started", elapsedMilliseconds: 0)
    }

    func mark(_ stage: String) {
        log(stage: stage, elapsedMilliseconds: elapsedMilliseconds)
    }

    func finish(totalLabel: String = "total") {
        log(stage: totalLabel, elapsedMilliseconds: elapsedMilliseconds)
    }

    private var elapsedMilliseconds: Double {
        let duration = startedAt.duration(to: clock.now)
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private func log(stage: String, elapsedMilliseconds: Double) {
        guard Self.isEnabled else {
            return
        }

        let contextLabel = context.map { " [\($0)]" } ?? ""
        let message = String(
            format: "%@%@ (%@) - %@: %.2f ms",
            name,
            contextLabel,
            identifier,
            stage,
            elapsedMilliseconds
        )
        Self.logger.debug("\(message, privacy: .public)")
    }
}
