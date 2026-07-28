import Darwin
import Foundation

@main
enum RegressionTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    static func main() {
        testRedHighUsageWindowOutranksGreenWindow()
        testColorTierOutranksPercentage()
        testProcessOutputIsReturned()
        testProcessIsTerminatedAtTimeout()
        print("All regression tests passed")
    }

    private static func testRedHighUsageWindowOutranksGreenWindow() {
        let green = window(percent: 80, elapsedPercent: 80)
        let red = window(percent: 95, elapsedPercent: 95)
        check(
            Pace.severity(green, now: now) < Pace.severity(red, now: now),
            "95% red window must outrank 80% green window"
        )
    }

    private static func testColorTierOutranksPercentage() {
        let green = window(percent: 80, elapsedPercent: 80)
        let red = window(percent: 50, elapsedPercent: 25)
        check(
            Pace.severity(green, now: now) < Pace.severity(red, now: now),
            "red pace window must outrank higher-percentage green window"
        )
    }

    private static func testProcessOutputIsReturned() {
        let output = Fetcher.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["hello"],
            timeout: 1
        )
        check(
            output.flatMap { String(data: $0, encoding: .utf8) } == "hello",
            "successful helper process must return stdout"
        )
    }

    private static func testProcessIsTerminatedAtTimeout() {
        let startedAt = Date()
        let output = Fetcher.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.1
        )
        check(output == nil, "timed-out helper process must return nil")
        check(
            Date().timeIntervalSince(startedAt) < 2,
            "timed-out helper process must be terminated promptly"
        )
    }

    private static func window(percent: Double, elapsedPercent: Double) -> UsageWindow {
        let length = 1_000
        let remaining = Double(length) * (1 - elapsedPercent / 100)
        return UsageWindow(
            label: "\(percent)",
            percent: percent,
            resetsAt: Int(now.timeIntervalSince1970 + remaining),
            windowSeconds: length
        )
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
