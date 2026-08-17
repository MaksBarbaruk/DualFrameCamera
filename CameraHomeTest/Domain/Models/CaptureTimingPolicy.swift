import Foundation

nonisolated struct CaptureTimingPolicy: Equatable, Sendable {
    static let standard = CaptureTimingPolicy(
        rearToFrontIntervalNanoseconds: 1_500_000_000
    )

    let rearToFrontIntervalNanoseconds: UInt64

    func frontTarget(afterRearUptime rearUptime: UInt64) -> UInt64 {
        let (target, overflow) = rearUptime.addingReportingOverflow(
            rearToFrontIntervalNanoseconds
        )
        return overflow ? UInt64.max : target
    }

    func remainingDelay(
        afterRearUptime rearUptime: UInt64,
        currentUptime: UInt64
    ) -> UInt64 {
        let target = frontTarget(afterRearUptime: rearUptime)
        return target > currentUptime ? target - currentUptime : 0
    }
}
