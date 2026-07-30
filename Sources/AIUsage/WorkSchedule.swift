import Foundation

/// The part of the week the user intends to spend quota in. Times are stored as
/// minutes after local midnight so the preference survives time-zone changes;
/// concrete intervals are rebuilt with the current calendar whenever a target is
/// calculated.
struct WorkSchedule: Equatable {
    enum Weekday: Int, CaseIterable, Hashable, Identifiable {
        case sunday = 1
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday

        var id: Int { rawValue }

        static let mondayFirst: [Weekday] = [
            .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
        ]

        var shortLabel: String {
            switch self {
            case .monday: return "M"
            case .tuesday: return "T"
            case .wednesday: return "W"
            case .thursday: return "T"
            case .friday: return "F"
            case .saturday: return "S"
            case .sunday: return "S"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .sunday: return "Sunday"
            case .monday: return "Monday"
            case .tuesday: return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday: return "Thursday"
            case .friday: return "Friday"
            case .saturday: return "Saturday"
            }
        }
    }

    var enabled: Bool
    var weekdays: Set<Weekday>
    var startMinute: Int
    var endMinute: Int

    static let defaultWeekdays: Set<Weekday> = [
        .monday, .tuesday, .wednesday, .thursday, .friday,
    ]

    static let disabled = WorkSchedule(
        enabled: false,
        weekdays: defaultWeekdays,
        startMinute: 9 * 60,
        endMinute: 18 * 60
    )

    var isValid: Bool {
        !weekdays.isEmpty && Self.normalized(startMinute) != Self.normalized(endMinute)
    }

    var weekdayMask: Int {
        weekdays.reduce(0) { $0 | (1 << ($1.rawValue - 1)) }
    }

    init(enabled: Bool, weekdays: Set<Weekday>, startMinute: Int, endMinute: Int) {
        self.enabled = enabled
        self.weekdays = weekdays
        self.startMinute = Self.normalized(startMinute)
        self.endMinute = Self.normalized(endMinute)
    }

    init(enabled: Bool, weekdayMask: Int, startMinute: Int, endMinute: Int) {
        let decoded = Set(Weekday.allCases.filter {
            weekdayMask & (1 << ($0.rawValue - 1)) != 0
        })
        self.init(
            enabled: enabled,
            weekdays: decoded.isEmpty ? Self.defaultWeekdays : decoded,
            startMinute: startMinute,
            endMinute: endMinute
        )
    }

    /// True only while the working-hours calculation should be live. An
    /// overnight shift belongs to the weekday on which it starts.
    func isActive(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard enabled, isValid else { return false }
        let today = calendar.startOfDay(for: date)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return false
        }
        return [yesterday, today].contains { day in
            interval(startingOn: day, calendar: calendar)?.containsHalfOpen(date) == true
        }
    }

    /// Wall seconds covered by configured working intervals inside `range`.
    /// Building each boundary through `Calendar` makes spring-forward,
    /// fall-back and time-zone changes part of the interval rather than an
    /// arithmetic exception.
    func scheduledSeconds(
        in range: DateInterval,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TimeInterval {
        guard isValid, range.duration > 0 else { return 0 }
        var day = calendar.startOfDay(for: range.start)
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
            return 0
        }
        day = previous

        let last = calendar.startOfDay(for: range.end)
        var total: TimeInterval = 0

        while day <= last {
            if let work = interval(startingOn: day, calendar: calendar) {
                let start = max(work.start, range.start)
                let end = min(work.end, range.end)
                if end > start { total += end.timeIntervalSince(start) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }
        return total
    }

    /// The next point at which `isActive` can change, used to refresh the target
    /// without waiting for the provider polling interval.
    func nextBoundary(
        after date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard enabled, isValid else { return nil }
        let today = calendar.startOfDay(for: date)
        guard var day = calendar.date(byAdding: .day, value: -1, to: today) else {
            return nil
        }
        var candidates: [Date] = []

        // Eight days plus yesterday covers the end of an overnight shift and
        // the next occurrence of even a single selected weekday.
        for _ in 0..<10 {
            if let interval = interval(startingOn: day, calendar: calendar) {
                if interval.start > date { candidates.append(interval.start) }
                if interval.end > date { candidates.append(interval.end) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }
        return candidates.min()
    }

    // ----------------------------------------------------------------- //

    private func interval(startingOn day: Date, calendar: Calendar) -> DateInterval? {
        let weekday = calendar.component(.weekday, from: day)
        guard let selected = Weekday(rawValue: weekday), weekdays.contains(selected),
              let start = localTime(startMinute, on: day, calendar: calendar)
        else { return nil }

        let overnight = endMinute < startMinute
        guard let endDay = overnight
            ? calendar.date(byAdding: .day, value: 1, to: day)
            : Optional(day),
              let end = localTime(endMinute, on: endDay, calendar: calendar),
              end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func localTime(_ minute: Int, on day: Date, calendar: Calendar) -> Date? {
        let value = Self.normalized(minute)
        let components = DateComponents(hour: value / 60, minute: value % 60, second: 0)
        return calendar.nextDate(
            after: day.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func normalized(_ minute: Int) -> Int {
        min(1439, max(0, minute))
    }
}

private extension DateInterval {
    /// `DateInterval.contains` includes the end; schedules switch to wall clock
    /// exactly at their end time, so their membership is half-open instead.
    func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
