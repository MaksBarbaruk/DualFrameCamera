import Testing
@testable import CameraHomeTest

struct CaptureTimingPolicyTests {
    private let policy = CaptureTimingPolicy.standard

    @Test
    func standardTargetIsExactlyOnePointFiveSecondsAfterRearFrame() {
        let rearUptime: UInt64 = 8_000_000_000

        let target = policy.frontTarget(afterRearUptime: rearUptime)

        #expect(target == 9_500_000_000)
    }

    @Test
    func remainingDelayCompensatesForWorkAfterRearFrame() {
        let delay = policy.remainingDelay(
            afterRearUptime: 8_000_000_000,
            currentUptime: 8_275_000_000
        )

        #expect(delay == 1_225_000_000)
    }

    @Test
    func lateSchedulingCapturesFrontWithoutAnExtraDelay() {
        let delay = policy.remainingDelay(
            afterRearUptime: 8_000_000_000,
            currentUptime: 9_700_000_000
        )

        #expect(delay == 0)
    }
}
