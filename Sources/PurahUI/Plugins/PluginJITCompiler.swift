// Sources/PurahUI/Plugins/PluginJITCompiler.swift
import Foundation
import PurahCore

@MainActor
public final class PluginJITCompiler {
    public static let shared = PluginJITCompiler()

    private init() {}

    /// Locates the active swift CLI tool
    private func swiftExecutableURL() -> URL {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/swift") {
            return URL(fileURLWithPath: "/usr/bin/swift")
        }
        return URL(fileURLWithPath: "/usr/bin/xcrun")
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

        let process = Process()
        process.currentDirectoryURL = packageDir
        process.executableURL = swiftExecutableURL()
        process.arguments = [
            "build",
            "-c", configuration,
            "--disable-sandbox"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PluginDynamicLoadError.compilationFailed(output)
        }

        // Resolve built binary directory
        let binPathProcess = Process()
        binPathProcess.currentDirectoryURL = packageDir
        binPathProcess.executableURL = swiftExecutableURL()
        binPathProcess.arguments = [
            "build",
            "-c", configuration,
            "--disable-sandbox",
            "--show-bin-path"
        ]
        let binPipe = Pipe()
        binPathProcess.standardOutput = binPipe
        try binPathProcess.run()
        binPathProcess.waitUntilExit()

        let binData = binPipe.fileHandleForReading.readDataToEndOfFile()
        let binPath = (String(data: binData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

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
