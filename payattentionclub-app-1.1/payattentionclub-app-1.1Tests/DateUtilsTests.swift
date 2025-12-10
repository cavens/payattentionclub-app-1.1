import XCTest
@testable import payattentionclub_app_1_1

/// Unit tests for date calculations and countdown formatting
final class DateUtilsTests: XCTestCase {
    
    // MARK: - Countdown Formatting Tests
    
    func testFormatCountdown_Zero() {
        let result = DateCalculator.formatCountdown(timeInterval: 0)
        XCTAssertEqual(result, "00:00:00:00", "Zero time should format as all zeros")
    }
    
    func testFormatCountdown_Negative() {
        let result = DateCalculator.formatCountdown(timeInterval: -100)
        XCTAssertEqual(result, "00:00:00:00", "Negative time should format as all zeros")
    }
    
    func testFormatCountdown_OneMinute() {
        let result = DateCalculator.formatCountdown(timeInterval: 60)
        XCTAssertEqual(result, "00:00:01:00", "60 seconds should be 1 minute")
    }
    
    func testFormatCountdown_OneHour() {
        let result = DateCalculator.formatCountdown(timeInterval: 3600)
        XCTAssertEqual(result, "00:01:00:00", "3600 seconds should be 1 hour")
    }
    
    func testFormatCountdown_OneDay() {
        let result = DateCalculator.formatCountdown(timeInterval: 86400)
        XCTAssertEqual(result, "01:00:00:00", "86400 seconds should be 1 day")
    }
    
    func testFormatCountdown_ComplexTime() {
        // 2 days, 14 hours, 30 minutes, 45 seconds
        let days: TimeInterval = 2 * 86400
        let hours: TimeInterval = 14 * 3600
        let minutes: TimeInterval = 30 * 60
        let seconds: TimeInterval = 45
        let interval = days + hours + minutes + seconds
        let result = DateCalculator.formatCountdown(timeInterval: interval)
        XCTAssertEqual(result, "02:14:30:45", "Should format as DD:HH:MM:SS")
    }
    
    func testFormatCountdown_MaxWeek() {
        // 7 days
        let days: TimeInterval = 7
        let interval = days * 86400
        let result = DateCalculator.formatCountdown(timeInterval: interval)
        XCTAssertEqual(result, "07:00:00:00", "7 days should format correctly")
    }
    
    // MARK: - Minutes Remaining Tests
    
    func testMinutesRemaining_Future() {
        let now = Date()
        let future = now.addingTimeInterval(3600) // 1 hour from now
        
        let minutes = DateCalculator.minutesRemaining(from: now, to: future)
        XCTAssertEqual(minutes, 60.0, accuracy: 0.1, "Should return 60 minutes")
    }
    
    func testMinutesRemaining_Past() {
        let now = Date()
        let past = now.addingTimeInterval(-3600) // 1 hour ago
        
        let minutes = DateCalculator.minutesRemaining(from: now, to: past)
        XCTAssertEqual(minutes, 0.0, "Should return 0 for past deadlines")
    }
    
    func testMinutesRemaining_Same() {
        let now = Date()
        let minutes = DateCalculator.minutesRemaining(from: now, to: now)
        XCTAssertEqual(minutes, 0.0, "Should return 0 when same time")
    }
    
    // MARK: - Next Monday Calculation Tests
    
    func testNextMondayNoonEST_ReturnsMonday() {
        let nextMonday = DateCalculator.calculateNextMondayNoonEST()
        
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        let weekday = estCalendar.component(.weekday, from: nextMonday)
        XCTAssertEqual(weekday, 2, "Result should be a Monday (weekday 2)")
    }
    
    func testNextMondayNoonEST_ReturnsNoon() {
        let nextMonday = DateCalculator.calculateNextMondayNoonEST()
        
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        let hour = estCalendar.component(.hour, from: nextMonday)
        XCTAssertEqual(hour, 12, "Result should be at noon (hour 12)")
    }
    
    func testNextMondayNoonEST_IsFuture() {
        let now = Date()
        let nextMonday = DateCalculator.calculateNextMondayNoonEST(from: now)
        
        // Note: If it's Monday before noon, nextMonday could be today
        // Otherwise it should be in the future
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        let nowWeekday = estCalendar.component(.weekday, from: now)
        let nowHour = estCalendar.component(.hour, from: now)
        
        if nowWeekday == 2 && nowHour < 12 {
            // It's Monday before noon, so next Monday is today at noon
            XCTAssertGreaterThanOrEqual(nextMonday, now, "Next Monday should be >= now on Monday morning")
        } else {
            XCTAssertGreaterThan(nextMonday, now, "Next Monday should be in the future")
        }
    }
    
    func testNextMondayNoonEST_FromSunday() {
        // Create a Sunday at 3 PM EST
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 14 // Sunday Dec 14, 2025
        components.hour = 15
        components.minute = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        
        guard let sunday = estCalendar.date(from: components) else {
            XCTFail("Could not create Sunday date")
            return
        }
        
        let nextMonday = DateCalculator.calculateNextMondayNoonEST(from: sunday)
        
        let resultDay = estCalendar.component(.day, from: nextMonday)
        XCTAssertEqual(resultDay, 15, "Next Monday from Dec 14 Sunday should be Dec 15")
    }
    
    func testNextMondayNoonEST_FromMondayMorning() {
        // Create a Monday at 10 AM EST (before noon)
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15 // Monday Dec 15, 2025
        components.hour = 10
        components.minute = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        
        guard let mondayMorning = estCalendar.date(from: components) else {
            XCTFail("Could not create Monday morning date")
            return
        }
        
        let nextMonday = DateCalculator.calculateNextMondayNoonEST(from: mondayMorning)
        
        let resultDay = estCalendar.component(.day, from: nextMonday)
        let resultHour = estCalendar.component(.hour, from: nextMonday)
        
        XCTAssertEqual(resultDay, 15, "On Monday morning, next Monday noon should be same day")
        XCTAssertEqual(resultHour, 12, "Should be at noon")
    }
    
    func testNextMondayNoonEST_FromMondayAfternoon() {
        // Create a Monday at 2 PM EST (after noon)
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15 // Monday Dec 15, 2025
        components.hour = 14
        components.minute = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        
        guard let mondayAfternoon = estCalendar.date(from: components) else {
            XCTFail("Could not create Monday afternoon date")
            return
        }
        
        let nextMonday = DateCalculator.calculateNextMondayNoonEST(from: mondayAfternoon)
        
        let resultDay = estCalendar.component(.day, from: nextMonday)
        XCTAssertEqual(resultDay, 22, "On Monday afternoon, next Monday should be next week (Dec 22)")
    }
}

