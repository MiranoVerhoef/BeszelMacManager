import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combined: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return out + "\n" + err
    }
}

enum Shell {
    static let knownBrewPaths: [String] = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    static func run(_ launchPath: String, _ args: [String], env: [String: String] = [:]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: "Failed to run: \(launchPath) \(args.joined(separator: " "))\n\(error)")
        }

        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    static func bash(_ command: String) -> ShellResult {
        let envPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return run("/bin/bash", ["-lc", command], env: ["PATH": envPath])
    }

    static func detectBrewPath() -> String? {
        for p in knownBrewPaths {
            let res = run(p, ["--version"])
            if res.exitCode == 0 { return p }
        }
        let res = bash("command -v brew")
        let candidate = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty {
            let test = run(candidate, ["--version"])
            if test.exitCode == 0 { return candidate }
        }
        return nil
    }

    static func brew(_ args: [String]) -> ShellResult {
        guard let brewPath = detectBrewPath() else {
            return ShellResult(
                exitCode: 127,
                stdout: "",
                stderr: "Homebrew not found (or blocked by App Sandbox). Install Homebrew, or disable App Sandbox in Xcode for this MVP."
            )
        }
        return run(brewPath, args)
    }
}
