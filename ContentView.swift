import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { callback(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { callback(nsView.window) }
    }
}

struct ContentView: View {
    @State private var key: String = ""
    @State private var token: String = ""
    @State private var hubURL: String = ""
    @State private var listen: String = "45876"

    @State private var envPreserve = EnvFile.Parsed()

    @State private var output: String = ""
    @State private var logText: String = ""
    @State private var autoRefreshLog: Bool = true
    @State private var showSandboxHelp: Bool = false

    @State private var didSetWindowTitle: Bool = false

    private let serviceName = "beszel-agent"

    private var isSandboxed: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    private var brewPath: String? {
        Shell.detectBrewPath()
    }

    private var appShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }

    private var appVersionString: String {
        "v\(appShortVersion) (\(appBuild))"
    }

    private var windowTitle: String {
        "Beszel Mac Manager \(appVersionString)"
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            if isSandboxed {
                sandboxBanner
            }

            HStack(alignment: .top, spacing: 14) {
                leftColumn
                rightColumn
            }

            outputBox

            footer
        }
        .padding(14)
        .frame(minWidth: 980, minHeight: 760)
        .background(
            WindowAccessor { window in
                guard let w = window else { return }
                if !didSetWindowTitle {
                    w.title = windowTitle
                    didSetWindowTitle = true
                }
            }
        )
        .onAppear {
            loadEnv()
            refreshLog()
            startLogTimer()
        }
        .sheet(isPresented: $showSandboxHelp) {
            sandboxHelpSheet
        }
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Beszel Mac Manager")
                    .font(.system(size: 22, weight: .semibold))
                Text("Easy MVP • Homebrew-based • Controls agent service + edits env file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            GroupBox {
                HStack(spacing: 10) {
                    Text(appVersionString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospaced()

                    Divider()
                        .frame(height: 16)

                    Image(systemName: brewPath == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(brewPath == nil ? .orange : .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(brewPath == nil ? "Homebrew: Not detected" : "Homebrew: OK")
                            .font(.headline)
                        Text(brewPath ?? "Install Homebrew or disable App Sandbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 10)

                    if brewPath == nil {
                        Button("Install Homebrew") { installHomebrewInTerminal() }
                        Button("Open brew.sh") { openURL("https://brew.sh") }
                    }
                }
                .frame(width: 520)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(isSandboxed ? "Sandbox: ON (recommended OFF for MVP)" : "Sandbox: OFF")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(appVersionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
        }
        .padding(.top, 2)
    }

    // MARK: - Sandbox help

    private var sandboxBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("App Sandbox is enabled — this breaks brew + real Beszel paths")
                    .font(.headline)
                Text("Disable App Sandbox in Xcode: Target → Signing & Capabilities → remove App Sandbox.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("How to fix") { showSandboxHelp = true }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sandboxHelpSheet: some View {
        let steps = [
            "Disable App Sandbox (Xcode):",
            "1) Select your project (blue icon) in the navigator",
            "2) Select your app target",
            "3) Open Signing & Capabilities",
            "4) Remove App Sandbox (or uncheck it)",
            "5) Run again"
        ].joined(separator: "\n")

        return VStack(alignment: .leading, spacing: 12) {
            Text("Disable App Sandbox (Xcode)")
                .font(.title2).bold()

            Text(steps)
                .font(.body)

            Text("Why: sandboxed apps run in a container home and cannot access /opt/homebrew and ~/.config without extra entitlements.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Copy steps") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(steps, forType: .string)
                }
                Spacer()
                Button("Close") { showSandboxHelp = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(18)
        .frame(width: 560)
    }

    // MARK: - Columns

    private var leftColumn: some View {
        VStack(spacing: 14) {
            configBox
            serviceBox
        }
        .frame(maxWidth: 460)
    }

    private var rightColumn: some View {
        VStack(spacing: 14) {
            pathsBox
            logBox
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Config

    private var configBox: some View {
        GroupBox("Agent configuration") {
            VStack(spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("KEY").font(.headline)
                        TextEditor(text: $key)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }

                    GridRow {
                        Text("LISTEN").font(.headline)
                        TextField("45876", text: $listen)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                    }

                    GridRow {
                        Text("TOKEN").font(.headline)
                        TextField("optional", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text("HUB_URL").font(.headline)
                        TextField("optional", text: $hubURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 6)

                HStack(spacing: 10) {
                    Button("Load env") { loadEnv() }
                    Button("Save env") { saveEnv() }
                    Spacer()
                    Button("Copy TOKEN") { copyToClipboard(token) }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Service

    private var serviceBox: some View {
        GroupBox("Service controls (brew services)") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Install agent (brew)") { installViaBrew() }
                    Button("Update agent") { runBrew(["upgrade", serviceName]) }
                    Spacer()
                    Button("Status") { status() }
                }

                HStack(spacing: 10) {
                    Button("Start") { runBrew(["services", "start", serviceName]) }
                    Button("Stop") { runBrew(["services", "stop", serviceName]) }
                    Button("Restart") { runBrew(["services", "restart", serviceName]) }
                    Spacer()
                    Button("Open HUB_URL") { openHub() }
                }

                Divider().padding(.top, 2)

                HStack(spacing: 10) {
                    Button("Install Homebrew") { installHomebrewInTerminal() }
                    Button("Open brew.sh") { openURL("https://brew.sh") }
                    Spacer()
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Paths

    private var pathsBox: some View {
        GroupBox("Paths") {
            VStack(alignment: .leading, spacing: 8) {
                pathRow(title: "Env file", path: EnvFile.envPath)
                pathRow(title: "Log file", path: EnvFile.logPath)

                Divider().padding(.vertical, 2)

                HStack {
                    Button("Open env in Finder") { openInFinder(path: EnvFile.envPath) }
                    Button("Open log in Finder") { openInFinder(path: EnvFile.logPath) }
                    Spacer()
                }
            }
            .padding(.top, 6)
        }
    }

    private func pathRow(title: String, path: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .frame(width: 70, alignment: .leading)

            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button("Copy") { copyToClipboard(path) }
        }
    }

    // MARK: - Logs

    private var logBox: some View {
        GroupBox("Agent log (tail)") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Toggle("Auto refresh", isOn: $autoRefreshLog)
                    Button("Refresh now") { refreshLog() }
                    Spacer()
                    Button("Clear view") { logText = "" }
                }

                ScrollView {
                    Text(logText.isEmpty ? "No log loaded yet." : logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(height: 320)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Output

    private var outputBox: some View {
        GroupBox("Command output") {
            ScrollView {
                Text(output.isEmpty ? "Ready." : output)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(height: 200)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .padding(.top, 6)
        }
    }

    // MARK: - Actions

    private func append(_ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        output = "[\(ts)] \(text)\n" + output
    }

    private func runBrew(_ args: [String]) {
        let res = Shell.brew(args)
        append("$ brew \(args.joined(separator: " "))\n\(res.combined)")
        refreshLog()
    }

    private func installViaBrew() {
        runBrew(["tap", "henrygd/beszel"])
        runBrew(["install", serviceName])
        runBrew(["services", "start", serviceName])
    }

    private func status() {
        runBrew(["services", "info", serviceName])
    }

    private func loadEnv() {
        envPreserve = EnvFile.read()
        key = envPreserve.values["KEY"] ?? ""
        token = envPreserve.values["TOKEN"] ?? ""
        hubURL = envPreserve.values["HUB_URL"] ?? ""
        listen = envPreserve.values["LISTEN"] ?? "45876"
        append("Loaded env from \(EnvFile.envPath)")
    }

    private func saveEnv() {
        do {
            try EnvFile.write(
                key: key,
                token: token,
                hubURL: hubURL,
                listen: listen,
                preserve: envPreserve
            )
            append("Saved env to \(EnvFile.envPath)")
        } catch {
            append("Failed saving env: \(error)")
        }
    }

    private func refreshLog() {
        logText = EnvFile.tailLog()
    }

    private func startLogTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if autoRefreshLog { refreshLog() }
        }
    }

    private func openHub() {
        let urlStr = hubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlStr), !urlStr.isEmpty else {
            append("HUB_URL is empty or invalid.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openURL(_ urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        append("Copied to clipboard.")
    }

    private func escapeForAppleScript(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func installHomebrewInTerminal() {
        let cmd = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        let script = "tell application \"Terminal\" to do script \"\(escapeForAppleScript(cmd))\""
        let res = Shell.run("/usr/bin/osascript", ["-e", script])
        append("Opened Terminal for Homebrew install.\n\(res.combined)")
    }
}
