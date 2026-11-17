// Sources/PurahUI/Plugins/PluginJITCompiler.swift
import Foundation
import PurahCore

@MainActor
public final class PluginJITCompiler {
    public static let shared = PluginJITCompiler()

    public private(set) var lastCompilationError: String? = nil

    private init() {}

    /// Locates the active swift CLI tool
    nonisolated private static func swiftExecutableURL() -> URL {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/swift") {
            return URL(fileURLWithPath: "/usr/bin/swift")
        }
        return URL(fileURLWithPath: "/usr/bin/xcrun")
    }

    nonisolated private static func runProcessOffMainThread(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) async throws -> (status: Int32, output: String) {
        guard let executablePath = ProcessLaunchSanitizer.executablePath(executableURL.path) else {
            throw PluginDynamicLoadError.compilationFailed("Swift executable path is invalid.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ProcessLaunchSanitizer.argumentList(arguments)
        process.currentDirectoryURL = currentDirectoryURL
        // The manifest and any build-tool plugins run inside `swift build`, so
        // they see this environment. The app's own secrets — the terminal
        // bridge token, the rendered-secrets file path — have no business in a
        // third-party package's build. An allowlist beats a filter because a
        // new secret does not have to remember to use the `PURAH_` prefix.
        let allowedEnvironmentKeys: Set<String> = [
            "PATH", "HOME", "TMPDIR", "USER", "SHELL", "SDKROOT", "LANG", "LC_ALL",
            // The toolchain the person selected in Xcode, so a plugin builds
            // against the SDK the app was built with.
            "DEVELOPER_DIR",
        ]
        let environment = ProcessInfo.processInfo.environment.filter {
            allowedEnvironmentKeys.contains($0.key)
        }
        process.environment = ProcessLaunchSanitizer.environment(environment)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        final class BufferBox: @unchecked Sendable {
            let lock = NSLock()
            var data = Data()

            func append(_ chunk: Data) {
                guard !chunk.isEmpty else { return }
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }

            func finalize(remaining: Data) -> String {
                lock.lock()
                defer { lock.unlock() }
                if !remaining.isEmpty {
                    data.append(remaining)
                }
                return String(data: data, encoding: .utf8) ?? ""
            }
        }

        final class ContinuationGuard: @unchecked Sendable {
            let lock = NSLock()
            var isResumed = false

            func resumeOnce(_ action: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                if !isResumed {
                    isResumed = true
                    action()
                }
            }
        }

        let buffer = BufferBox()
        let resumeGuard = ContinuationGuard()
        let fileHandle = pipe.fileHandleForReading

        fileHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            buffer.append(chunk)
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                fileHandle.readabilityHandler = nil
                let remaining = fileHandle.readDataToEndOfFile()
                try? fileHandle.close()
                let outputString = buffer.finalize(remaining: remaining)
                resumeGuard.resumeOnce {
                    continuation.resume(returning: (proc.terminationStatus, outputString))
                }
            }

            do {
                try process.run()
            } catch {
                fileHandle.readabilityHandler = nil
                try? fileHandle.close()
                resumeGuard.resumeOnce {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Compiles a local Swift package folder into a dynamic library (.dylib)
    public func compilePackage(
        packageDir: URL,
        configuration: String = "release"
    ) async throws -> URL {
        let packageSwiftPath = packageDir.appendingPathComponent("Package.swift").path
        guard FileManager.default.fileExists(atPath: packageSwiftPath) else {
            throw PluginDynamicLoadError.fileNotFound(packageSwiftPath)
        }

        let buildResult = try await Self.runProcessOffMainThread(
            executableURL: Self.swiftExecutableURL(),
            // SwiftPM's own sandbox stays on. It costs a legitimate plugin
            // nothing (a plain dynamic library builds inside it) and it is the
            // only thing standing between a package's manifest or prebuild
            // plugin and this user's files.
            arguments: [
                "build",
                "-c", configuration
            ],
            currentDirectoryURL: packageDir
        )

        guard buildResult.status == 0 else {
            throw PluginDynamicLoadError.compilationFailed(buildResult.output)
        }

        // Resolve built binary directory
        let binPathResult = try await Self.runProcessOffMainThread(
            executableURL: Self.swiftExecutableURL(),
            arguments: [
                "build",
                "-c", configuration,
                "--show-bin-path"
            ],
            currentDirectoryURL: packageDir
        )

        let binPath = binPathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !binPath.isEmpty && FileManager.default.fileExists(atPath: binPath) else {
            throw PluginDynamicLoadError.fileNotFound("Could not resolve binary output directory for package at \(packageDir.path)")
        }

        let binURL = URL(fileURLWithPath: binPath)
        let contents = (try? FileManager.default.contentsOfDirectory(at: binURL, includingPropertiesForKeys: nil)) ?? []
        guard let dylib = contents.first(where: { $0.pathExtension == "dylib" }) else {
            throw PluginDynamicLoadError.fileNotFound("No .dylib found in \(binPath). Ensure Package.swift declares .library(..., type: .dynamic, ...).")
        }

        return dylib
    }

    /// Compiles and loads a local Swift Package for security review without activating it.
    public func compileAndLoadForReview(
        packageDir: URL,
        configuration: String = "release"
    ) async -> (dylibURL: URL, plugin: any PurahPodPlugin)? {
        lastCompilationError = nil
        do {
            let dylib = try await compilePackage(packageDir: packageDir, configuration: configuration)
            let plugin = try PluginDynamicLoader.shared.loadPlugin(from: dylib)
            return (dylib, plugin)
        } catch {
            lastCompilationError = error.localizedDescription
            DiagnosticLogger.shared.warn("Plugin", "compileAndLoadForReview failed for \(packageDir.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Activates and mounts a plugin that has been approved through security confirmation.
    public func activateReviewedPlugin(
        _ plugin: any PurahPodPlugin,
        dylibURL: URL,
        packageDir: URL? = nil,
        store: PurahWorkspaceStore
    ) {
        PluginDynamicLoader.shared.rememberInstalled(
            path: dylibURL.path,
            packagePath: packageDir?.path,
            for: plugin.manifest.id
        )
        PluginRegistry.shared.register(plugin, store: store)
        store.marketManager.install(id: plugin.manifest.id)
        store.autoLayoutAll()
    }

    /// High-level convenience: compiles local package, dynamically loads it, and mounts to workspace
    @discardableResult
    public func buildAndLoad(
        packageDir: URL,
        store: PurahWorkspaceStore,
        configuration: String = "release"
    ) async throws -> any PurahPodPlugin {
        guard let (dylib, plugin) = await compileAndLoadForReview(packageDir: packageDir, configuration: configuration) else {
            throw PluginDynamicLoadError.compilationFailed(
                lastCompilationError ?? "Failed to compile or load package at \(packageDir.path)"
            )
        }
        activateReviewedPlugin(plugin, dylibURL: dylib, packageDir: packageDir, store: store)
        return plugin
    }

    // MARK: - Git Sideloading Helpers

    /// Runs a git command off the main actor if git is available.
    @discardableResult
    nonisolated public static func runGit(
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) async throws -> (status: Int32, output: String) {
        let gitPath = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: gitPath) else {
            throw PluginDynamicLoadError.compilationFailed("git executable not found at \(gitPath)")
        }
        let workDir = currentDirectoryURL ?? FileManager.default.temporaryDirectory
        return try await runProcessOffMainThread(
            executableURL: URL(fileURLWithPath: gitPath),
            arguments: arguments,
            currentDirectoryURL: workDir
        )
    }

    /// Pulls latest changes for a package directory if it is a git repository.
    public func gitPullIfRepository(packageDir: URL) async {
        let gitDir = packageDir.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else { return }
        do {
            let res = try await Self.runGit(
                arguments: ["-C", packageDir.path, "pull", "--ff-only"],
                currentDirectoryURL: packageDir
            )
            if res.status != 0 {
                DiagnosticLogger.shared.warn("Plugin", "git pull --ff-only returned \(res.status): \(res.output)")
            } else {
                DiagnosticLogger.shared.info("Plugin", "git pull succeeded for \(packageDir.lastPathComponent)")
            }
        } catch {
            DiagnosticLogger.shared.warn("Plugin", "git pull failed for \(packageDir.path): \(error.localizedDescription)")
        }
    }

    /// Clones or updates a git repository into destination directory.
    public func cloneOrPullGitRepository(from gitURL: URL, into parentDir: URL) async throws -> URL {
        let rawName = gitURL.deletingPathExtension().lastPathComponent
        let sanitizedName = rawName.isEmpty ? "PurahPlugin" : rawName
        let targetDir = parentDir.appendingPathComponent(sanitizedName, isDirectory: true)

        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: targetDir.appendingPathComponent(".git").path) {
            await gitPullIfRepository(packageDir: targetDir)
            return targetDir
        }

        let res = try await Self.runGit(
            arguments: ["clone", "--depth", "1", gitURL.absoluteString, targetDir.path],
            currentDirectoryURL: parentDir
        )
        guard res.status == 0 else {
            throw PluginDynamicLoadError.compilationFailed("git clone failed:\n\(res.output)")
        }
        return targetDir
    }
}
