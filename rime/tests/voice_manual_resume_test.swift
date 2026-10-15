import AppKit
@MainActor final class ReproHost: VoiceTextHost {
 let view = NSTextView()
 var selection: NSRange { view.selectedRange() }
 var marked: NSRange { view.markedRange() }
 func text(in r:NSRange)->String? { guard NSMaxRange(r)<=view.string.utf16.count else {return nil}; return (view.string as NSString).substring(with:r) }
 func mark(_ t:String,replacing r:NSRange){view.setMarkedText(t,selectedRange:NSRange(location:t.utf16.count,length:0),replacementRange:r)}
 func insert(_ t:String,replacing r:NSRange){view.insertText(t,replacementRange:r)}
}
@main struct FixedOrderTest {
 @MainActor static func main(){
  let host=ReproHost(), editing=VoiceEditing(); var transcript=VoiceTranscript()
  precondition(editing.begin(host))
  func final(_ text:String,_ start:Double,_ end:Double){transcript.update(text:text,start:start,end:end,final:true);if editing.receive(text,final:true){transcript.delivered(start:start)}}
  final("测试豆包语音。",0,2)
  editing.protect();host.view.insertText("mac",replacementRange:NSRange(location:NSNotFound,length:0))
  precondition(editing.resumeAfterManualEdit())
  precondition(editing.receive("请你", final:false))
  final("请你继续输入。",3,4);final("好的。",5,6)
  let remainder=transcript.remaining
  precondition(remainder.isEmpty)
  precondition(host.view.string=="测试豆包语音。mac请你继续输入。好的。")
  print("PASS: manual mac preserved and subsequent speech stays chronological: "+host.view.string)
  editing.protect(); host.view.setSelectedRange(NSRange(location:0,length:2))
  precondition(!editing.resumeAfterManualEdit()); precondition(host.view.string.contains("mac"))
  print("PASS: selection is protected rather than overwritten on resumption")
 }
}
