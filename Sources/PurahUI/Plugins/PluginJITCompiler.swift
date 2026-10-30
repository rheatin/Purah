// Sources/PurahUI/Plugins/PluginJITCompiler.swift
import Foundation
import PurahCore

@MainActor
public final class PluginJITCompiler {
    public static let shared = PluginJITCompiler()

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
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        // The manifest and any build-tool plugins run inside `swift build`, so
        // they see this environment. The app's own secrets — the terminal
        // bridge token, the rendered-secrets file path — have no business in a
        // third-party package's build.
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PURAH_") }

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

    /// High-level convenience: compiles local package, dynamically loads it, and mounts to workspace
    @discardableResult
    public func buildAndLoad(
        packageDir: URL,
        store: PurahWorkspaceStore,
        configuration: String = "release"
    ) async throws -> any PurahPodPlugin {
        let dylib = try await compilePackage(packageDir: packageDir, configuration: configuration)
        let plugin = try PluginDynamicLoader.shared.loadPlugin(from: dylib)

        PluginRegistry.shared.register(plugin, store: store)
        store.marketManager.install(id: plugin.manifest.id)
        store.autoLayoutAll()

        return plugin
    }
}
