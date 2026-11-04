// Tests/PurahCoreTests/ProcessDisplayNameResolverTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("Process Display Name Resolver")
struct ProcessDisplayNameResolverTests {
    private let appPath = "/Applications/网易叭哥说.app"
    private var appBundles: [String: ProcessAppBundleInfo] {
        [
            appPath: ProcessAppBundleInfo(
                displayName: "网易叭哥说",
                executableName: "网易叭哥说"
            )
        ]
    }

    @Test("An app main executable uses the app display name")
    func appMainExecutableUsesBundleName() {
        let executable = "\(appPath)/Contents/MacOS/网易叭哥说"
        let name = ProcessDisplayNameResolver.resolve(
            pid: 100,
            executablePath: executable,
            fallbackName: "A page title, not a process name",
            processTable: [100: .init(parentPID: 1, executablePath: executable)],
            appBundles: appBundles
        )

        #expect(name == "网易叭哥说")
    }

    @Test("A WebKit XPC rolls up to the owning app and keeps its helper name")
    func webKitXPCUsesOwningApp() {
        let appExecutable = "\(appPath)/Contents/MacOS/网易叭哥说"
        let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        let table: [Int32: ProcessExecutableRecord] = [
            100: .init(parentPID: 1, executablePath: appExecutable),
            200: .init(parentPID: 100, executablePath: webContent)
        ]

        let name = ProcessDisplayNameResolver.resolve(
            pid: 200,
            executablePath: webContent,
            fallbackName: "网易叭哥说 网页内容",
            processTable: table,
            appBundles: appBundles
        )

        #expect(name == "网易叭哥说 · WebContent")
    }

    @Test("Apple XPC service names keep the useful final component")
    func appleXPCServiceNamesAreShortened() {
        #expect(
            ProcessDisplayNameResolver.helperShortName(
                for: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
            ) == "GPU"
        )
        #expect(
            ProcessDisplayNameResolver.helperShortName(
                for: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking"
            ) == "Networking"
        )
    }

    @Test("A helper inside an app is qualified instead of masquerading as the app")
    func appHelperIsQualified() {
        let executable = "\(appPath)/Contents/Helpers/Network Helper"
        let name = ProcessDisplayNameResolver.resolve(
            pid: 300,
            executablePath: executable,
            fallbackName: nil,
            processTable: [300: .init(parentPID: 100, executablePath: executable)],
            appBundles: appBundles
        )

        #expect(name == "网易叭哥说 · Network Helper")
    }

    @Test("An empty bundle display name falls back to the app bundle basename")
    func emptyBundleDisplayNameFallsBack() {
        let executable = "/Applications/PlainName.app/Contents/MacOS/PlainName"
        let bundlePath = "/Applications/PlainName.app"
        let name = ProcessDisplayNameResolver.resolve(
            pid: 350,
            executablePath: executable,
            fallbackName: nil,
            processTable: [350: .init(parentPID: 1, executablePath: executable)],
            appBundles: [
                bundlePath: ProcessAppBundleInfo(
                    displayName: "   ",
                    executableName: "PlainName"
                )
            ]
        )

        #expect(name == "PlainName")
    }

    @Test("A version-named executable uses its meaningful parent directory")
    func versionNamedExecutableUsesParentName() {
        let executable = "/Users/char/Library/Application Support/Tern/omp/versions/18.12.6"
        let name = ProcessDisplayNameResolver.resolve(
            pid: 400,
            executablePath: executable,
            fallbackName: "18.12.6",
            processTable: [400: .init(parentPID: 1, executablePath: executable)]
        )

        #expect(name == "omp 18.12.6")
    }

    @Test("Version detection accepts only digit-and-dot basenames with an optional v")
    func versionDetectionIsNarrow() {
        #expect(ProcessDisplayNameResolver.isBareVersion("18.12.6"))
        #expect(ProcessDisplayNameResolver.isBareVersion("2.1"))
        #expect(ProcessDisplayNameResolver.isBareVersion("v1.4.0"))
        #expect(!ProcessDisplayNameResolver.isBareVersion("version1.4"))
        #expect(!ProcessDisplayNameResolver.isBareVersion("1.4-beta"))
        #expect(!ProcessDisplayNameResolver.isBareVersion("1..4"))
    }

    @Test("A non-bundle path uses its executable basename")
    func nonBundleExecutableUsesBasename() {
        let executable = "/usr/local/bin/purah-helper"
        let name = ProcessDisplayNameResolver.resolve(
            pid: 500,
            executablePath: executable,
            fallbackName: "Ignored fallback",
            processTable: [500: .init(parentPID: 1, executablePath: executable)]
        )

        #expect(name == "purah-helper")
    }

    @Test("An empty path falls back to a friendly name and then the PID")
    func emptyPathAlwaysProducesAName() {
        #expect(
            ProcessDisplayNameResolver.resolve(
                pid: 600,
                executablePath: "",
                fallbackName: "kernel_task",
                processTable: [:]
            ) == "kernel_task"
        )
        #expect(
            ProcessDisplayNameResolver.resolve(
                pid: 601,
                executablePath: "   ",
                fallbackName: "\n",
                processTable: [:]
            ) == "pid 601"
        )
    }

    @Test("An ancestor cycle stops safely instead of hanging")
    func ancestorCycleIsBounded() {
        let helper = "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        let table: [Int32: ProcessExecutableRecord] = [
            700: .init(parentPID: 701, executablePath: helper),
            701: .init(parentPID: 700, executablePath: "/bin/zsh")
        ]

        let name = ProcessDisplayNameResolver.resolve(
            pid: 700,
            executablePath: helper,
            fallbackName: nil,
            processTable: table
        )

        #expect(name == "WebContent")
    }

    @Test("Path-component helpers preserve Foundation's naming results")
    func pathComponentHelpersMatchResolverNames() {
        #expect(
            ProcessDisplayNameResolver.lastPathComponent(
                of: "/Users/char/Library/Application Support/Tern/omp/versions/18.12.6"
            ) == "18.12.6"
        )
        #expect(
            ProcessDisplayNameResolver.versionedName(
                for: "/Users/char/Library/Application Support/Tern/omp/versions/18.12.6",
                executableName: "18.12.6"
            ) == "omp 18.12.6"
        )
        #expect(
            ProcessDisplayNameResolver.appBundlePath(
                in: "/Applications/网易叭哥说.app/Contents/MacOS/网易叭哥说"
            ) == "/Applications/网易叭哥说.app"
        )
    }
}
