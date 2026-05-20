import Testing
@testable import CodexNotifierHelper

@Suite("Codex notifier helper")
struct CodexNotifierHelperTests {
    @Test("app launch arguments keep Codex Notifier in the background")
    func appLaunchArgumentsKeepNotifierInBackground() {
        #expect(CodexNotifierHelper.backgroundOpenArguments(appPath: nil) == ["-g", "-a", "Codex Notifier"])
    }

    @Test("app path launch arguments keep Codex Notifier in the background")
    func appPathLaunchArgumentsKeepNotifierInBackground() {
        #expect(
            CodexNotifierHelper.backgroundOpenArguments(appPath: "/Applications/Codex Notifier.app")
                == ["-g", "/Applications/Codex Notifier.app"]
        )
    }
}
