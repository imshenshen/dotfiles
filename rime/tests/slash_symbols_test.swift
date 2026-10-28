import Foundation

@main struct SlashSymbolsTest {
  static func main() {
    let data = SlashSymbolData.all
    precondition(data.count == 158, "expected 158 non-ASCII /fh symbols, got \(data.count)")
    precondition(Set(data.map(\.glyph)).count == data.count)
    precondition(Set(data.map(\.hex)).count == data.count)
    for symbol in data {
      precondition(symbol.glyph.unicodeScalars.count == 1)
      let code = symbol.glyph.unicodeScalars.first!.value
      precondition(!(0x20...0x7E).contains(code), "ASCII leaked into catalog: \(symbol.glyph)")
      precondition(symbol.hex == String(format: "U+%04X", code))
      precondition(!symbol.category.isEmpty)
    }

    let index = SlashSymbolIndex.shared
    let categories = index.categories
    precondition(categories.first == "全部")
    precondition(Set(categories.dropFirst()) == Set(data.map(\.category)))
    precondition(categories.count == data.map(\.category).reduce(into: Set<String>()) { $0.insert($1) }.count + 1)

    precondition(index.search("copyright").first?.glyph == "©")
    precondition(index.search("版权").contains { $0.glyph == "©" })
    precondition(index.search("banquan").contains { $0.glyph == "©" })
    precondition(index.search("U+00A9").first?.glyph == "©")
    precondition(index.search("00a9").first?.glyph == "©")
    precondition(index.search("gear").first?.glyph == "⚙")
    precondition(index.search("chilun").first?.glyph == "⚙")
    precondition(index.search("yinyang").first?.glyph == "☯")
    precondition(index.search("shandian").first?.glyph == "⚡")
    precondition(index.search("zzzz-no-symbol").isEmpty)
    precondition(index.search("").count == data.count)

    let sports = index.symbols(in: "体育与娱乐")
    precondition(!sports.isEmpty && sports.allSatisfy { $0.category == "体育与娱乐" })
    precondition(index.search("", category: "体育与娱乐") == sports)
    precondition(index.search("ball", category: "体育与娱乐").allSatisfy { $0.category == "体育与娱乐" })
    precondition(index.search("copyright", category: "体育与娱乐").isEmpty)

    let initials = index.search("bq")
    precondition(initials.contains { $0.glyph == "©" || $0.glyph == "®" })
    print("PASS: 158 unique non-ASCII symbols; category coverage; glyph, hex, English, Chinese, pinyin and initials search; filters respect category")
  }
}
