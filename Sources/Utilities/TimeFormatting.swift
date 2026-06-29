import Foundation

func formatTimestamp(_ seconds: TimeInterval) -> String {
    let totalMilliseconds = Int((seconds * 1000).rounded())
    let milliseconds = totalMilliseconds % 1000
    let totalSeconds = totalMilliseconds / 1000
    let second = totalSeconds % 60
    let minute = (totalSeconds / 60) % 60
    let hour = totalSeconds / 3600
    return String(format: "%02d:%02d:%02d,%03d", hour, minute, second, milliseconds)
}

func formatClock(_ seconds: TimeInterval) -> String {
    let totalMilliseconds = Int((seconds * 1000).rounded())
    let milliseconds = totalMilliseconds % 1000
    let totalSeconds = totalMilliseconds / 1000
    let second = totalSeconds % 60
    let minute = (totalSeconds / 60) % 60
    let hour = totalSeconds / 3600
    return String(format: "%02d:%02d:%02d.%03d", hour, minute, second, milliseconds)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let safe = max(0, Int(seconds.rounded()))
    let hour = safe / 3600
    let minute = (safe % 3600) / 60
    let second = safe % 60
    if hour > 0 {
        return String(format: "%02d:%02d:%02d", hour, minute, second)
    }
    return String(format: "%02d:%02d", minute, second)
}

func parseTimestamp(_ string: String) -> TimeInterval? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",."))
    guard parts.count == 2 else { return nil }
    let clock = parts[0].split(separator: ":").map(String.init)
    guard clock.count == 3 else { return nil }
    guard
        let hour = Double(clock[0]),
        let minute = Double(clock[1]),
        let second = Double(clock[2])
    else {
        return nil
    }
    let milliseconds = Double(parts[1].padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
    return hour * 3600 + minute * 60 + second + milliseconds / 1000
}

func normalizeTimestampString(from raw: String) -> String? {
    let trimmed = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "，", with: ",")
        .replacingOccurrences(of: "。", with: ".")

    if let seconds = parseTimestamp(trimmed) {
        return formatClock(seconds)
    }

    let components = trimmed
        .components(separatedBy: CharacterSet(charactersIn: ":,."))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !components.isEmpty else { return nil }

    let numbers = components.compactMap(Int.init)
    guard numbers.count == components.count else { return nil }

    let hours: Int
    let minutes: Int
    let seconds: Int
    let milliseconds: Int

    switch numbers.count {
    case 4:
        hours = numbers[0]
        minutes = numbers[1]
        seconds = numbers[2]
        milliseconds = numbers[3]
    case 3:
        hours = 0
        minutes = numbers[0]
        seconds = numbers[1]
        milliseconds = numbers[2]
    case 2:
        hours = 0
        minutes = numbers[0]
        seconds = numbers[1]
        milliseconds = 0
    case 1:
        hours = 0
        minutes = 0
        seconds = numbers[0]
        milliseconds = 0
    default:
        return nil
    }

    let total = Double(hours * 3600 + minutes * 60 + seconds) + Double(milliseconds) / 1000
    return formatClock(total)
}
