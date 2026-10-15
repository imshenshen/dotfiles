import Foundation
@main struct FormattingTest {
  static func main() {
    let entries = [VoiceDictionaryEntry(output: "AI助手", code: "aizs", weight: "10", spoken: "人工智能助手"),
                   VoiceDictionaryEntry(output: "Mac 电脑", code: "mac", weight: "", spoken: "苹果电脑"),
                   VoiceDictionaryEntry(output: "Cat", code: "cat", weight: "", spoken: "at")]
    let on = VoiceTextFormatter(spaces: true, entries: entries), off = VoiceTextFormatter(spaces: false, entries: entries)
    precondition(on.format("今天用Mac写了3个文件") == "今天用 Mac 写了 3 个文件")
    precondition(off.format("今天用 Mac 写了 3 个文件") == "今天用Mac写了3个文件")
    precondition(on.format("使用AI助手和Mac 电脑") == "使用 AI助手和 Mac 电脑")
    precondition(off.format("使用AI 助手和Mac电脑") == "使用AI助手和Mac 电脑")
    precondition(on.format("使用人工智能助手和苹果电脑", voice: true) == "使用 AI助手和 Mac 电脑")
    precondition(on.format("使用人工智能助手") == "使用人工智能助手")
    precondition(on.format("cat scat", voice: true) == "Cat scat")
    precondition(on.format("你好\nMac", previous: "", following: "") == "你好\nMac")
    precondition(on.format("Mac", previous: "我用", following: "写作") == " Mac ")
    precondition(off.format("Mac", previous: "我用 ", following: " 写作") == "Mac")
    precondition(on.format(on.format("使用AI助手和Mac 电脑")) == "使用 AI助手和 Mac 电脑")
    precondition(on.format("1。中文 2．English 3.结束") == "1.中文 2.English 3.结束")
    precondition(on.format("1 。中文 2 .英文") == "1.中文 2.英文")
    precondition(off.format("1。中文 2．English") == "1.中文 2.English")
    precondition(on.format("v1。测试 3.14 1.2.3") == "v1。测试 3.14 1.2.3")
    precondition(on.format("。", previous: " 12") == ".")
    precondition(on.format("。", previous: "12", previousAtStart: true) == ".")
    precondition(on.format("。", previous: "v12") == "。")
    let protected = VoiceTextFormatter(spaces: true, entries: [.init(output: "1。原样", code: "one", weight: "", spoken: "")])
    precondition(protected.format("1。原样") == "1。原样")
    var transcript = VoiceTranscript()
    transcript.update(text: on.format("今天用"), start: 0, end: 1, final: true)
    transcript.update(text: on.format("Mac"), start: 2, end: 3, final: true)
    precondition(on.format(transcript.remaining) == "今天用 Mac")
    print("PASS: Chinese/English/digit spacing on and off, exact dictionary spans, voice aliases, word boundaries, newlines, surrounding text, idempotence")
  }
}
