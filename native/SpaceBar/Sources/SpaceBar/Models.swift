import Foundation

struct Space: Decodable, Equatable {
    let id: Int
    let index: Int
    let label: String
    let display: Int
    let focused: Bool
    let visible: Bool
    let fullscreen: Bool
    enum CodingKeys: String, CodingKey {
        case id, index, label, display
        case focused = "has-focus", visible = "is-visible", fullscreen = "is-native-fullscreen"
    }
    var name: String { label.isEmpty ? "Space \(index)" : label }
    var hint: String { (1...9).contains(index) ? String(Array("QWERTYUIO")[index - 1]) : String(index) }
}
struct Display: Decodable, Equatable {
    let id: UInt32
    let index: Int
}
struct Snapshot: Equatable {
    var spaces: [Space]
    var displays: [Display]
    func spaces(on id: UInt32) -> [Space] {
        guard let display = displays.first(where: { $0.id == id }) else { return [] }
        return spaces.filter { $0.display == display.index }.sorted { $0.index < $1.index }
    }
}
struct BarError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func validatedName(_ value: String, id: Int, spaces: [Space]) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 80, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        throw BarError(message: "名称需为 1–80 个字符，不能包含换行或控制字符。")
    }
    guard !spaces.contains(where: { $0.id != id && $0.label == name }) else {
        throw BarError(message: "其他 Space 已使用这个名称。")
    }
    return name
}
func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
