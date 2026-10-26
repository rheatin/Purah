// Sources/PurahCore/Services/LocalSkillDiscoveryService.swift
import Foundation

@Observable
@MainActor
public final class LocalSkillDiscoveryService {
    public static let shared = LocalSkillDiscoveryService()

    public private(set) var discoveredSkills: [AILocalSkill] = []

    public init() {}

    public func scanSkills(config: AIBuiltInSkillConfig) -> [AILocalSkill] {
        guard config.enableLocalSkills else {
            self.discoveredSkills = []
            return []
        }

        let searchLocations: [(path: String, source: AILocalSkillSource)] = [
            ("~/.agents/skills", .optimus),
            ("~/.config/optimus/skills", .optimus),
            ("~/.claude/skills", .claude),
            ("~/Library/Application Support/Purah/Skills", .purah)
        ] + config.customSkillDirectories.map { ($0, .custom) }

        var results: [AILocalSkill] = []
        var seenIds = Set<String>()

        let fileManager = FileManager.default

        for location in searchLocations {
            let expandedRoot = (location.path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: expandedRoot, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let entries = try? fileManager.contentsOfDirectory(atPath: expandedRoot) else {
                continue
            }

            for entry in entries.sorted() {
                guard !entry.hasPrefix(".") else { continue }
                let folderPath = (expandedRoot as NSString).appendingPathComponent(entry)
                var entryIsDir: ObjCBool = false
                guard fileManager.fileExists(atPath: folderPath, isDirectory: &entryIsDir), entryIsDir.boolValue else {
                    continue
                }

                let candidates = ["SKILL.md", "skill.md", "README.md"]
                var matchedFile: String? = nil
                for candidate in candidates {
                    let candidatePath = (folderPath as NSString).appendingPathComponent(candidate)
                    if fileManager.fileExists(atPath: candidatePath) {
                        matchedFile = candidatePath
                        break
                    }
                }

                guard let skillFilePath = matchedFile,
                      let rawContent = try? String(contentsOfFile: skillFilePath, encoding: .utf8) else {
                    continue
                }

                if var skill = parseSkill(content: rawContent, folderName: entry, folderPath: folderPath, source: location.source) {
                    if !seenIds.contains(skill.id) {
                        seenIds.insert(skill.id)
                        skill.isEnabled = !config.disabledSkillIds.contains(skill.id)
                        results.append(skill)
                    }
                }
            }
        }

        self.discoveredSkills = results
        return results
    }

    // MARK: - Skill Markdown Parsing
    public nonisolated func parseSkill(content: String, folderName: String, folderPath: String, source: AILocalSkillSource) -> AILocalSkill? {
        let lines = content.components(separatedBy: .newlines)

        var startIndex: Int? = nil
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                startIndex = i
                break
            } else if !trimmed.isEmpty {
                break
            }
        }

        var parsedName: String? = nil
        var parsedDescription: String? = nil
        var promptBody = ""

        if let start = startIndex {
            var endIndex: Int? = nil
            for i in (start + 1)..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    endIndex = i
                    break
                }
            }

            if let end = endIndex {
                let frontmatterLines = lines[(start + 1)..<end]
                var currentKey: String? = nil
                var currentValue = ""

                for fLine in frontmatterLines {
                    let trimmedLine = fLine.trimmingCharacters(in: .whitespaces)
                    if trimmedLine.hasPrefix("name:") {
                        commitFrontmatter(key: currentKey, value: currentValue, name: &parsedName, description: &parsedDescription)
                        currentKey = "name"
                        currentValue = String(trimmedLine.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces)
                    } else if trimmedLine.hasPrefix("description:") {
                        commitFrontmatter(key: currentKey, value: currentValue, name: &parsedName, description: &parsedDescription)
                        currentKey = "description"
                        currentValue = String(trimmedLine.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces)
                    } else if currentKey != nil && (fLine.hasPrefix("  ") || fLine.hasPrefix("\t")) {
                        if !currentValue.isEmpty { currentValue += " " }
                        currentValue += trimmedLine
                    } else if trimmedLine.contains(":") {
                        commitFrontmatter(key: currentKey, value: currentValue, name: &parsedName, description: &parsedDescription)
                        currentKey = nil
                        currentValue = ""
                    }
                }
                commitFrontmatter(key: currentKey, value: currentValue, name: &parsedName, description: &parsedDescription)

                if (end + 1) < lines.count {
                    promptBody = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                promptBody = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            promptBody = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let displayName = parsedName?.trimmingCharacters(in: .whitespacesAndNewlines).strippingQuotes() ?? ""
        let finalName = displayName.isEmpty ? folderName : displayName

        let finalDescription: String
        if let desc = parsedDescription?.trimmingCharacters(in: .whitespacesAndNewlines).strippingQuotes(), !desc.isEmpty {
            finalDescription = desc
        } else {
            finalDescription = extractFallbackDescription(from: promptBody, fallback: finalName)
        }

        let trigger = sanitizeTrigger(finalName.isEmpty ? folderName : finalName)

        return AILocalSkill(
            id: folderName,
            name: finalName,
            description: finalDescription,
            trigger: trigger,
            directoryPath: folderPath,
            promptTemplate: promptBody,
            isEnabled: true,
            source: source
        )
    }

    private nonisolated func commitFrontmatter(key: String?, value: String, name: inout String?, description: inout String?) {
        guard let key else { return }
        let cleaned = value.strippingQuotes()
        if key == "name" && !cleaned.isEmpty {
            name = cleaned
        } else if key == "description" && !cleaned.isEmpty {
            description = cleaned
        }
    }

    private nonisolated func extractFallbackDescription(from body: String, fallback: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                let headerText = trimmed.drop(while: { $0 == "#" || $0 == " " })
                if !headerText.isEmpty {
                    return String(headerText)
                }
            } else {
                let sentence = trimmed.prefix(while: { $0 != "." && $0 != "\n" })
                if !sentence.isEmpty {
                    return String(sentence) + (trimmed.contains(".") ? "." : "")
                }
                return trimmed
            }
        }
        return fallback
    }

    private nonisolated func sanitizeTrigger(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let converted = trimmed.replacingOccurrences(of: " ", with: "-")
        let filtered = converted.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return filtered.isEmpty ? "skill" : filtered
    }
}

extension String {
    fileprivate func strippingQuotes() -> String {
        var trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        if trimmed.hasPrefix(">") || trimmed.hasPrefix("|") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
