import Testing
@testable import PurahCore

@Suite("Process Launch Sanitizer")
struct ProcessLaunchSanitizerTests {
    @Test("U+0000 is removed from arguments while other whitespace survives")
    func stripsNulFromArguments() {
        let argument = ProcessLaunchSanitizer.argument("lead\u{0}ing-mid\u{0}dle-trail\u{0}")
        let preserved = ProcessLaunchSanitizer.argument("line one\nline two\tindented")

        #expect(argument == "leading-middle-trail")
        #expect(preserved == "line one\nline two\tindented")
    }

    @Test("Argument lists sanitize every element, including empty results")
    func sanitizesArgumentLists() {
        let values = ProcessLaunchSanitizer.argumentList([
            "a\u{0}b",
            "\u{0}",
            "new\nline"
        ])

        #expect(values == ["ab", "", "new\nline"])
    }

    @Test("Environment keys and values lose U+0000 and empty keys are dropped")
    func sanitizesEnvironment() {
        let values = ProcessLaunchSanitizer.environment([
            "A\u{0}B": "x\u{0}y",
            "\u{0}": "dropped",
            "KEEP": "line\n\tvalue"
        ])

        #expect(values == [
            "AB": "xy",
            "KEEP": "line\n\tvalue"
        ])
    }

    @Test("Executable paths must be absolute and free of U+0000")
    func validatesExecutablePaths() {
        #expect(ProcessLaunchSanitizer.executablePath("/bin/zsh") == "/bin/zsh")
        #expect(ProcessLaunchSanitizer.executablePath("") == nil)
        #expect(ProcessLaunchSanitizer.executablePath("bin/zsh") == nil)
        #expect(ProcessLaunchSanitizer.executablePath("/bin/z\u{0}sh") == nil)
    }
}
