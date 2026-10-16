import Foundation

struct VoiceDictionaryEntry: Codable, Equatable {
  var output: String
  var code: String
  var weight: String
  var spoken: String
  var doubaoHotword: Bool? = nil // Old dictionaries remain opt-out.
}

// Dictionary spans are immutable; only ordinary Chinese/Latin boundaries change.
struct VoiceTextFormatter {
  let spaces: Bool
  let entries: [VoiceDictionaryEntry]
  private struct Unit { let character: Character; let protected: Int? }
  static func han(_ c: Character) -> Bool {
    c.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) || (0x20000...0x323af).contains($0.value) }
  }
  static func latin(_ c: Character) -> Bool {
    c.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || (0xc0...0x24f).contains($0.value) }
  }
  static func boundary(_ a: Character, _ b: Character) -> Bool { han(a) && latin(b) || latin(a) && han(b) }
  func format(_ text: String, voice: Bool = false, previous: String = "", following: String = "", previousAtStart: Bool = false) -> String {
    var rules: [(String, String)] = []
    for entry in entries where !entry.output.isEmpty {
      rules.append((entry.output, entry.output))
      if voice && !entry.spoken.isEmpty { rules.append((entry.spoken, entry.output)) }
    }
    rules.sort { $0.0.count > $1.0.count }
    // Tolerate ASR-inserted spaces at Chinese/Latin boundaries when matching a
    // dictionary term; its output itself remains byte-for-byte as configured.
    let patterns = rules.compactMap { input, output -> (NSRegularExpression, String)? in
      let normalized = input.replacingOccurrences(of: "(?<=[\\p{Han}])[ \\t]+(?=[A-Za-z0-9])|(?<=[A-Za-z0-9])[ \\t]+(?=[\\p{Han}])", with: "", options: .regularExpression)
      let chars = Array(normalized); var pattern = ""
      if let first = chars.first, Self.latin(first) { pattern += "(?<![A-Za-z0-9])" }
      for i in chars.indices {
        if i > 0 && Self.boundary(chars[i-1], chars[i]) { pattern += "[ \\t]*" }
        pattern += NSRegularExpression.escapedPattern(for: String(chars[i]))
      }
      if let last = chars.last, Self.latin(last) { pattern += "(?![A-Za-z0-9])" }
      guard let regex = try? NSRegularExpression(pattern: pattern, options: voice ? [.caseInsensitive] : []) else { return nil }
      return (regex, output)
    }
    var units: [Unit] = []; var cursor = text.startIndex; var group = 0
    while cursor < text.endIndex {
      let range = NSRange(cursor..<text.endIndex, in: text)
      if let rule = patterns.first(where: { $0.0.firstMatch(in: text, options: [.anchored, .withTransparentBounds], range: range) != nil }),
         let match = rule.0.firstMatch(in: text, options: [.anchored, .withTransparentBounds], range: range),
         let matched = Range(match.range, in: text) {
        group += 1; units += rule.1.map { Unit(character: $0, protected: group) }; cursor = matched.upperBound
      } else { units.append(Unit(character: text[cursor], protected: nil)); cursor = text.index(after: cursor) }
    }
    // A list number begins at a whitespace/start boundary and is immediately
    // followed by a period. Do this after dictionary matching to preserve terms.
    for index in units.indices.reversed() where units[index].protected == nil && (units[index].character == "。" || units[index].character == "．" || units[index].character == ".") {
      var numberEnd = index
      while numberEnd > 0 && units[numberEnd-1].protected == nil && (units[numberEnd-1].character == " " || units[numberEnd-1].character == "\t") { numberEnd -= 1 }
      var start = numberEnd
      while start > 0 && units[start-1].protected == nil && units[start-1].character.isASCII && units[start-1].character.isNumber { start -= 1 }
      var preceding: Character? = start > 0 ? units[start-1].character : nil
      var hasDigits = start < numberEnd
      var atStart = start == 0 && previous.isEmpty
      if start == 0 && !previous.isEmpty {
        let prefix = Array(previous); var before = prefix.count
        while before > 0 && prefix[before-1].isASCII && prefix[before-1].isNumber { before -= 1 }
        hasDigits = hasDigits || before < prefix.count
        preceding = before > 0 ? prefix[before-1] : nil
        atStart = before == 0 && previousAtStart
      }
      if hasDigits && (atStart || preceding?.isWhitespace == true) {
        if start > 0, units[start-1].protected == nil, units[start-1].character.isWhitespace {
          units[start-1] = Unit(character: units[start-1].character, protected: -1)
        }
        units.removeSubrange(numberEnd..<index)
        units[numberEnd] = Unit(character: ".", protected: nil)
      }
    }
    var result = ""; var index = 0
    while index < units.count {
      let current = units[index]
      if (current.character == " " || current.character == "\t") && current.protected == nil {
        var end = index
        while end < units.count && units[end].protected == nil && (units[end].character == " " || units[end].character == "\t") { end += 1 }
        if index > 0 && end < units.count && Self.boundary(units[index-1].character, units[end].character) {
          if spaces { result += " " }; index = end; continue
        }
      }
      if index > 0, Self.boundary(units[index-1].character, current.character),
         current.protected == nil || current.protected != units[index-1].protected, spaces { result += " " }
      result.append(current.character); index += 1
    }
    // Never remove or rewrite existing document characters (including user spaces).
    if spaces, let a = previous.last, let b = result.first, Self.boundary(a, b) { result = " " + result }
    if spaces, let a = result.last, let b = following.first, Self.boundary(a, b) { result += " " }
    return result
  }
}

// Keep a right-side separator outside an English word being typed one key at a
// time. Only replace a separator created by this instance, at the same caret
// position and with unchanged surrounding text; never consume a user's space.
struct DirectTextSpacing {
  struct Insertion {
    let text: String
    let range: NSRange
  }
  private struct Gap {
    let caret: Int
    let before: String
    let following: String
  }
  private var gap: Gap?
  private static func contextSuffix(_ text: String) -> String {
    let value = text as NSString
    return value.substring(from: max(0, value.length - 32))
  }
  mutating func reset() { gap = nil }
  mutating func insertion(_ text: String, at selection: NSRange, previous: String,
                          following: String, formatter: VoiceTextFormatter) -> Insertion? {
    guard selection.location != NSNotFound, selection.length == 0,
          text.count == 1, let character = text.first, VoiceTextFormatter.latin(character),
          formatter.spaces else { reset(); return nil }
    var before = previous
    var replacement = selection
    if let gap, gap.caret == selection.location, gap.before == previous,
       gap.following == following, previous.hasSuffix(" "), selection.location > 0 {
      before.removeLast()
      replacement = NSRange(location: selection.location - 1, length: 1)
    }
    reset()
    let formatted = formatter.format(text, previous: before, following: following)
    guard formatted != text || replacement.length > 0 else { return nil }
    if formatted.hasSuffix(" "), let next = following.first, VoiceTextFormatter.han(next) {
      gap = Gap(caret: replacement.location + formatted.utf16.count,
                before: Self.contextSuffix(before + formatted), following: following)
    }
    return Insertion(text: formatted, range: replacement)
  }
}
