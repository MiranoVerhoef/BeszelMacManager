import Foundation

struct EnvFile {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static let envPath = (home as NSString).appendingPathComponent(".config/beszel/beszel-agent.env")
    static let logPath = (home as NSString).appendingPathComponent(".cache/beszel/beszel-agent.log")

    struct Parsed {
        var values: [String: String] = [:]
        var extraLines: [String] = []
    }

    static func ensureParentDir() throws {
        let url = URL(fileURLWithPath: envPath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func read() -> Parsed {
        var parsed = Parsed()
        guard FileManager.default.fileExists(atPath: envPath),
              let raw = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return parsed
        }

        let lines = raw.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") { parsed.extraLines.append(line); continue }

            guard let eq = trimmed.firstIndex(of: "=") else {
                parsed.extraLines.append(line)
                continue
            }

            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            if key.isEmpty {
                parsed.extraLines.append(line)
            } else {
                parsed.values[key] = value
            }
        }

        return parsed
    }

    static func write(key: String, token: String, hubURL: String, listen: String, preserve: Parsed) throws {
        try ensureParentDir()

        var lines: [String] = []

        func add(_ k: String, _ v: String, quoted: Bool) {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }

            if quoted {
                let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("\(k)=\"\(escaped)\"")
            } else {
                lines.append("\(k)=\(trimmed)")
            }
        }

        add("KEY", key, quoted: true)
        add("LISTEN", listen.isEmpty ? "45876" : listen, quoted: false)
        add("TOKEN", token, quoted: true)
        add("HUB_URL", hubURL, quoted: true)

        if !preserve.extraLines.isEmpty {
            lines.append("")
            lines.append("# ---- preserved lines ----")
            lines.append(contentsOf: preserve.extraLines)
        }

        let known = Set(["KEY", "TOKEN", "HUB_URL", "LISTEN"])
        let unknownPairs = preserve.values.filter { !known.contains($0.key) }
        if !unknownPairs.isEmpty {
            lines.append("")
            lines.append("# ---- preserved env vars ----")
            for k in unknownPairs.keys.sorted() {
                lines.append("\(k)=\(unknownPairs[k] ?? "")")
            }
        }

        let rendered = lines.joined(separator: "\n") + "\n"
        try rendered.write(toFile: envPath, atomically: true, encoding: .utf8)
    }

    static func tailLog(maxBytes: Int = 200_000) -> String {
        guard FileManager.default.fileExists(atPath: logPath) else {
            return "Log file not found: \(logPath)"
        }

        let url = URL(fileURLWithPath: logPath)
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            return "Unable to open log file."
        }
        defer { try? fh.close() }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: logPath)
            let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
            let offset = max(0, fileSize - maxBytes)
            try fh.seek(toOffset: UInt64(offset))
            let data = try fh.readToEnd() ?? Data()
            return String(data: data, encoding: .utf8) ?? "(log is not UTF-8)"
        } catch {
            return "Failed reading log: \(error)"
        }
    }
}
