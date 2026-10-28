import Foundation

@main struct SlashCommandTest {
  static func main() {
    precondition(SlashCommandMatch.match(input: "/fh", asciiMode: false) == .symbols)
    precondition(SlashCommandMatch.match(input: "/gif", asciiMode: false) == .gif)
    precondition(SlashCommandMatch.match(input: " /GIF\n", asciiMode: false) == .gif)
    precondition(SlashCommandMatch.match(input: "/fh", asciiMode: true) == nil)
    for input in ["/", "/f", "/fha", "/bq", "/mac", "//fh", "/fh/"] {
      precondition(SlashCommandMatch.match(input: input, asciiMode: false) == nil, "unexpected trigger: \(input)")
    }

    var state = SlashPaletteState(kind: .symbols)
    state.columns = 6; state.pageRows = 5; state.setItemCount(158)
    precondition(state.pageSize == 30 && state.pageCount == 6 && state.pageStart == 0)
    precondition(state.append("b") && state.append("a") && state.query == "ba" && state.selection == 0)
    precondition(!state.append("中") && !state.append("ab"))
    state.setItemCount(5)
    state.selection = 4
    state.move(dx: 1, dy: 0)
    precondition(state.selection == 4)
    state.move(dx: -2, dy: 0); precondition(state.selection == 2)
    state.move(dx: 0, dy: 1); precondition(state.selection == 4)
    state.page(up: false); precondition(state.selection == 4)
    state.page(up: true); precondition(state.selection == 0)

    state.setItemCount(95)
    state.selection = 31
    precondition(state.pageStart == 30 && state.pageNumber == 2)
    state.page(up: true); precondition(state.selection == 1 && state.pageStart == 0)
    state.page(up: false); precondition(state.selection == 31 && state.pageStart == 30)

    state.category = "警示与标志"
    state.selectCategory("全部"); precondition(state.category == nil)
    state.cycleCategory(["全部", "A", "B"], backwards: false); precondition(state.category == "A")
    state.cycleCategory(["全部", "A", "B"], backwards: true); precondition(state.category == nil)
    state.selectCategory("B")
    precondition(state.category == "B")

    state.query = ""
    precondition(state.backspace()) // empty query closes
    precondition(state.append("x"))
    precondition(!state.escape() && state.query.isEmpty)
    precondition(state.escape())
    precondition(state.backspace())

    state.setItemCount(0); state.selection = 9; state.clampSelection()
    precondition(state.selection == 0 && state.selectedIndex == nil)
    print("PASS: exact /fh and /gif only in Chinese mode; query editing; two-stage Escape; grid/page/category bounds")
  }
}
