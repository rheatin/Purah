// Sources/PurahCore/Services/ProcessDisplayNameResolver.swift
import Foundation

/// The executable facts needed to name one process. Paths and parent links are
/// injected so the resolution rules can be tested without the kernel.
struct ProcessExecutableRecord: Sendable, Equatable {
    let parentPID: Int32
    let executablePath: String?
}

struct ProcessAppBundleInfo: Sendable, Equatable {
    let displayName: String
    let executableName: String?
}

enum ProcessDisplayNameResolver {
    /// Deep enough for XPC nesting, but bounded so a malformed process tree
    /// cannot turn a label lookup into an unbounded walk.
    static let maxAncestorDepth = 12

    static func resolve(
        pid: Int32,
        executablePath: String?,
        fallbackName: String?,
        processTable: [Int32: ProcessExecutableRecord],
        appBundles: [String: ProcessAppBundleInfo] = [:]
    ) -> String {
        if let path = normalized(executablePath),
           let resolved = resolvePath(
               pid: pid,
               path: path,
               processTable: processTable,
               appBundles: appBundles
           ) {
            return resolved
        }

        if let fallbackName = normalized(fallbackName) {
            return fallbackName
        }
        return "pid \(pid)"
    }

    /// The outermost `.app` containing the executable. A nested helper app is
    /// still part of the person-facing app, and naming it after the helper
    /// bundle hides which app it belongs to.
    static func appBundlePath(in executablePath: String) -> String? {
        var current = (executablePath as NSString).standardizingPath
        var bundle: String?
        while current != "/" && !current.isEmpty {
            if (current as NSString).pathExtension.lowercased() == "app" {
                bundle = current
            }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current else { break }
            current = parent
        }
        return bundle
    }

    static func isBareVersion(_ name: String) -> Bool {
        var candidate = Substring(name)
        if candidate.first == "v" || candidate.first == "V" {
            candidate = candidate.dropFirst()
        }
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    static func helperShortName(for executablePath: String) -> String? {
        let components = executablePath.split(separator: "/").map(String.init)
        let executableName = lastPathComponent(of: executablePath)

        if let xpcComponent = components.first(where: { $0.lowercased().hasSuffix(".xpc") }) {
            let serviceName = String(xpcComponent.dropLast(".xpc".count))
            if let appleName = appleServiceLeaf(serviceName) {
                return appleName
            }
        }

        if let executableName, let appleName = appleServiceLeaf(executableName) {
            return appleName
        }
        return executableName
    }

    static func versionedName(for executablePath: String, executableName: String) -> String {
        let parentPath = (executablePath as NSString).deletingLastPathComponent
        let parentName = lastPathComponent(of: parentPath)
        if let parentName, !isGenericDirectory(parentName) {
            return "\(parentName) \(executableName)"
        }

        let grandparentPath = (parentPath as NSString).deletingLastPathComponent
        let grandparentName = lastPathComponent(of: grandparentPath)
        if let grandparentName, !isGenericDirectory(grandparentName) {
            return "\(grandparentName) \(executableName)"
        }
        return executableName
    }

    /// Foundation `URL` path component access parses RFC 3986. Process naming
    /// walks hundreds of paths every sample, where that parser is the hotspot.
    /// `NSString` performs the same path-component operation without it.
    static func lastPathComponent(of path: String) -> String? {
        normalized((path as NSString).lastPathComponent)
    }

    static func owningAppBundlePath(
        startingAt pid: Int32,
        processTable: [Int32: ProcessExecutableRecord]
    ) -> String? {
        var currentPID = pid
        var visited: Set<Int32> = []

        for _ in 0..<maxAncestorDepth {
            guard currentPID > 0,
                  visited.insert(currentPID).inserted,
                  let record = processTable[currentPID] else {
                return nil
            }
            if let path = normalized(record.executablePath),
               let bundlePath = appBundlePath(in: path) {
                return bundlePath
            }
            currentPID = record.parentPID
        }
        return nil
    }

    private static func resolvePath(
        pid: Int32,
        path: String,
        processTable: [Int32: ProcessExecutableRecord],
        appBundles: [String: ProcessAppBundleInfo]
    ) -> String? {
        let executableName = lastPathComponent(of: path)
        guard let executableName else { return nil }

        if let bundlePath = appBundlePath(in: path) {
            let app = appInfo(at: bundlePath, appBundles: appBundles)
            let isXPC = path.lowercased().contains(".xpc/")
            let mainExecutableName = normalized(app.executableName)
                ?? lastPathComponent(of: (bundlePath as NSString).deletingPathExtension)
            let isMainExecutable = !isXPC && executableName == mainExecutableName

            if isMainExecutable {
                return app.displayName
            }
            let helper = helperShortName(for: path) ?? executableName
            return "\(app.displayName) · \(helper)"
        }

        if path.lowercased().contains(".xpc/") {
            let helper = helperShortName(for: path) ?? executableName
            if let ownerPath = owningAppBundlePath(startingAt: pid, processTable: processTable) {
                let owner = appInfo(at: ownerPath, appBundles: appBundles)
                return "\(owner.displayName) · \(helper)"
            }
            return helper
        }

        if isBareVersion(executableName) {
            return versionedName(for: path, executableName: executableName)
        }
        return executableName
    }

    private static func appInfo(
        at bundlePath: String,
        appBundles: [String: ProcessAppBundleInfo]
    ) -> ProcessAppBundleInfo {
        let fallbackName = lastPathComponent(of: (bundlePath as NSString).deletingPathExtension) ?? bundlePath
        if let info = appBundles[bundlePath] {
            return ProcessAppBundleInfo(
                displayName: normalized(info.displayName) ?? fallbackName,
                executableName: normalized(info.executableName)
            )
        }
        return ProcessAppBundleInfo(displayName: fallbackName, executableName: nil)
    }

    private static func appleServiceLeaf(_ serviceName: String) -> String? {
        let prefix = "com.apple."
        guard serviceName.lowercased().hasPrefix(prefix) else { return nil }
        let remainder = String(serviceName.dropFirst(prefix.count))
        return normalized(remainder.split(separator: ".").last.map(String.init))
    }

    private static func isGenericDirectory(_ name: String) -> Bool {
        ["versions", "bin", "macos", "contents"].contains(name.lowercased())
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
