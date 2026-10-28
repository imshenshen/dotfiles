import Foundation

enum SlashSymbolData {}

struct SlashSymbol: Identifiable, Equatable {
  let glyph: String
  let nameEN: String
  let nameZH: String
  let pinyin: String
  let category: String
  let keywords: String
  let hex: String
  var id: String { hex }

  var searchText: String {
    [glyph, hex, nameEN, nameZH, pinyin, category, keywords]
      .joined(separator: " ")
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .lowercased()
  }
}

struct SlashSymbolIndex {
  static let shared = SlashSymbolIndex()
  static let categoryOrder = ["商标与版权", "警示与标志", "自然与地点", "体育与娱乐", "方向与手势", "工具与科学", "其他"]

  let symbols: [SlashSymbol]
  private let entries: [(symbol: SlashSymbol, text: String, initials: String)]

  // The curated catalog stores pinyin without syllable separators ("banquan").
  // These word-level expansions let initials search ("bq") stay useful without
  // shipping a full pinyin dictionary.
  private static let syllableInitials: [String: String] = [
    "baiqi": "bq",
    "bangqiu": "bq",
    "banquan": "bq",
    "biaoji": "bj",
    "biaozhi": "bz",
    "cha": "c",
    "chaxuan": "cx",
    "chilun": "cl",
    "chuanzhen": "cz",
    "chuizi": "cz",
    "dianhua": "dh",
    "didian": "dd",
    "dulun": "dl",
    "falun": "fl",
    "fanchuan": "fc",
    "fangkuang": "fk",
    "fangxiang": "fx",
    "fushe": "fs",
    "fuwu": "fw",
    "gao": "g",
    "gaoerfu": "gef",
    "gongju": "gj",
    "gouxuan": "gx",
    "heiqi": "hq",
    "heping": "hp",
    "hua": "h",
    "huabing": "hb",
    "huashi": "hs",
    "huaxue": "hx",
    "huishou": "hs",
    "jian": "j",
    "jiaotang": "jt",
    "jiayouzhan": "jyz",
    "jinggao": "jg",
    "jingshi": "js",
    "jinzhi": "jz",
    "kafei": "kf",
    "kexue": "kx",
    "kong": "k",
    "kulou": "kl",
    "lanqiu": "lq",
    "lian": "l",
    "luyin": "ly",
    "mao": "m",
    "penquan": "pq",
    "qita": "qt",
    "sanyecao": "syc",
    "shan": "s",
    "shandian": "sd",
    "shangbiao": "sb",
    "shangzhi": "sz",
    "shefuzuo": "sfz",
    "shengwu": "sw",
    "shenshe": "ss",
    "tianping": "tp",
    "toukui": "tk",
    "weihai": "wh",
    "wenquan": "wq",
    "wuzhangai": "wza",
    "xiazhi": "xz",
    "yiliao": "yl",
    "yinyang": "yy",
    "youzhi": "yz",
    "yuanwei": "yw",
    "yuanzi": "yz",
    "zhangpeng": "zp",
    "zhengliu": "zl",
    "zheyangsan": "zys",
    "zhuce": "zc",
    "ziran": "zr",
    "zuozhi": "zz",
    "zuqiu": "zq",
  ]

  init(symbols: [SlashSymbol] = SlashSymbolData.all) {
    self.symbols = symbols
    entries = symbols.map { symbol in
      let text = symbol.searchText
      let initials = Self.pinyin(symbol.pinyin).split(separator: " ")
        .map { Self.syllableInitials[String($0)] ?? String($0.prefix(1)) }
        .joined()
      return (symbol, text, initials)
    }
  }

  var categories: [String] {
    let present = Set(symbols.map(\.category))
    return ["全部"] + Self.categoryOrder.filter(present.contains) +
      present.subtracting(Self.categoryOrder).sorted()
  }

  func symbols(in category: String?) -> [SlashSymbol] {
    guard let category, category != "全部" else { return symbols }
    return symbols.filter { $0.category == category }
  }

  func search(_ rawQuery: String, category: String? = nil) -> [SlashSymbol] {
    let query = Self.normalize(rawQuery)
    let base = symbols(in: category)
    guard !query.isEmpty else { return base }
    let tokens = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return base }

    return base.compactMap { symbol -> (SlashSymbol, Int, Int)? in
      guard let entry = entries.first(where: { $0.symbol == symbol }) else { return nil }
      var score = 0
      for token in tokens {
        let glyph = symbol.glyph.lowercased()
        let hex = symbol.hex.lowercased()
        if token == glyph || token == hex || token == hex.replacingOccurrences(of: "u+", with: "") {
          score += 0
        } else if entry.initials.hasPrefix(token) || Self.normalize(symbol.nameEN).hasPrefix(token) ||
                    Self.normalize(symbol.pinyin).hasPrefix(token) {
          score += 1
        } else if entry.text.contains(token) || entry.initials.contains(token) {
          score += 3
        } else {
          return nil
        }
      }
      let categoryRank = Self.categoryOrder.firstIndex(of: symbol.category) ?? Self.categoryOrder.count
      return (symbol, score, categoryRank)
    }
    .sorted { lhs, rhs in
      if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
      if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
      return lhs.0.hex < rhs.0.hex
    }
    .map(\.0)
  }

  static func normalize(_ value: String) -> String {
    pinyin(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .lowercased()
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  static func pinyin(_ value: String) -> String {
    value.replacingOccurrences(of: "ü", with: "v").replacingOccurrences(of: "Ü", with: "v")
  }
}
