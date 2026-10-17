import Foundation

enum ExpectedFailure: Error { case injected }
final class Backend: SourceRecoveryBackend {
  var calls: [String] = []
  var enabled = true
  var modes: [String]
  var fail: String?
  init(_ modes: [String], fail: String? = nil) { self.modes = modes; self.fail = fail }
  func step(_ action: String) throws {
    calls.append(action)
    if fail == action { fail = nil; throw ExpectedFailure.injected }
  }
  func validate(modes: [String]) throws { try step("validate") }
  func disableParent() throws { enabled = false; modes = []; try step("disable") }
  func enableParent() throws { try step("enable"); enabled = true }
  func restoreModes(_ modes: [String]) throws { try step("restore"); self.modes = modes }
}
@main struct Tests {
  static func main() throws {
    let bundle = SourceRecoveryPolicy.bundle
    let hans = bundle + ".Hans", hant = bundle + ".Hant"
    let parent = ["Bundle ID": bundle, "InputSourceKind": "Keyboard Input Method"]
    let mode = ["Bundle ID": bundle, "Input Mode": hans, "InputSourceKind": "Input Mode"]
    assert(SourceRecoveryPolicy.modes([mode]) == nil)
    assert(SourceRecoveryPolicy.modes([parent]) == nil)
    assert(SourceRecoveryPolicy.modes([parent, mode, mode]) == nil)
    assert(SourceRecoveryPolicy.modes([parent, mode]) == [hans])
    let state = SourceRecoveryState(token: "test", generation: "2:123", version: "2", modes: [hans], phase: "pending", detail: "")
    assert(SourceRecoveryPolicy.ready(installerRunning: false, receipt: "2", state: state, generation: "2:123", modes: [hans]))
    for (running, receipt, generation, modes) in [(true,"2","2:123",[hans]), (false,"1","2:123",[hans]), (false,"2","2:456",[hans]), (false,"2","2:123",[hant])] {
      assert(!SourceRecoveryPolicy.ready(installerRunning: running, receipt: receipt, state: state, generation: generation, modes: modes))
    }
    for wanted in [[hans], [hant], [hans,hant]] {
      let backend = Backend(wanted)
      try rebuildSourceParent(backend, modes: wanted)
      assert(backend.enabled && backend.modes == wanted)
      assert(backend.calls == ["validate","disable","enable","restore"])
      for failure in ["disable","enable","restore"] {
        let broken = Backend(wanted, fail: failure)
        do { try rebuildSourceParent(broken, modes: wanted); assertionFailure("expected error") } catch ExpectedFailure.injected { }
        assert(broken.enabled && broken.modes == wanted, "rollback must preserve original mode choice")
      }
      let invalid = Backend(wanted, fail: "validate")
      do { try rebuildSourceParent(invalid, modes: wanted); assertionFailure("expected error") } catch ExpectedFailure.injected { }
      assert(invalid.calls == ["validate"] && invalid.enabled && invalid.modes == wanted)
    }
    print("PASS: installation gating, user mode choices, and restoration after partial failures")
  }
}
