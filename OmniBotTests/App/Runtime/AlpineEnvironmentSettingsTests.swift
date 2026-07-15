import Foundation
import Testing
@testable import Via_Vera

@Suite("Alpine environment settings")
@MainActor
struct AlpineEnvironmentSettingsTests {
    @Test("Detection selects missing packages and mirror changes persist")
    func modelState() async throws {
        let suiteName = "AlpineEnvironmentSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inventoryOutput = AlpineEnvironmentPackageDefinition.all.map { definition in
            if definition.id == "nodejs" {
                "__OMNI_ENV__\t\(definition.id)\tREADY\tv22.0.0"
            } else {
                "__OMNI_ENV__\t\(definition.id)\tMISSING\t"
            }
        }
        .joined(separator: "\n")
        let runner = TestAlpineEnvironmentCommandRunner(results: [
            commandResult(standardOutput: inventoryOutput),
            commandResult(),
        ])
        let model = AlpineEnvironmentSettingsModel(
            commandRunner: runner,
            userDefaults: defaults
        )

        await model.refreshInventory(selectMissingByDefault: true)
        #expect(model.readyCount == 1)
        #expect(model.selectedMissingCount == 8)
        #expect(!model.selectedPackageIDs.contains("nodejs"))

        model.selectedMirror = .tsinghua
        await model.applySelectedMirror()
        #expect(defaults.string(forKey: "alpine.packageMirror") == "tsinghua")
        #expect(runner.commands.last?.contains(AlpinePackageMirror.tsinghua.baseURL) == true)
    }

    @Test("Environment parity excludes Codex and parses package inventory")
    func definitionsAndInventory() {
        let definitions = AlpineEnvironmentPackageDefinition.all
        #expect(definitions.count == 9)
        #expect(!definitions.contains { $0.id == "codex" })

        let output = """
        noise
        __OMNI_ENV__\tnodejs\tREADY\tv22.0.0
        __OMNI_ENV__\tgit\tMISSING\t
        """
        let inventory = AlpineEnvironmentInventoryItem.parse(output)
        #expect(inventory["nodejs"] == AlpineEnvironmentInventoryItem(
            isReady: true,
            version: "v22.0.0"
        ))
        #expect(inventory["git"] == AlpineEnvironmentInventoryItem(
            isReady: false,
            version: nil
        ))
    }

    @Test("Install script applies selected mirror without Codex CLI")
    func installScript() throws {
        let selected = try [
            #require(AlpineEnvironmentPackageDefinition.all.first { $0.id == "uv" }),
            #require(AlpineEnvironmentPackageDefinition.all.first { $0.id == "openssh_server" }),
        ]
        let script = AlpineEnvironmentPackageDefinition.installationScript(
            for: selected,
            mirror: .tsinghua
        )

        #expect(script.contains("https://mirrors.tuna.tsinghua.edu.cn/alpine"))
        #expect(script.contains("apk add --no-cache python3 py3-pip openssh-server"))
        #expect(script.contains("python3 -m pip install --break-system-packages --upgrade uv"))
        #expect(script.contains("ssh-keygen -A"))
        #expect(!script.localizedCaseInsensitiveContains("codex"))
        #expect(!script.contains("@openai/codex"))
    }

    @Test("Mirror repository command follows installed Alpine branch")
    func mirrorCommands() {
        let official = AlpinePackageMirror.official.repositorySetupCommand
        let tsinghua = AlpinePackageMirror.tsinghua.repositorySetupCommand

        #expect(official.contains("/etc/alpine-release"))
        #expect(official.contains("https://dl-cdn.alpinelinux.org/alpine"))
        #expect(tsinghua.contains("https://mirrors.tuna.tsinghua.edu.cn/alpine"))
        #expect(tsinghua.contains("main\\n%s/%s/community"))
    }

    private func commandResult(standardOutput: String = "") -> AlpineCommandResult {
        AlpineCommandResult(
            executionID: UUID(),
            processIdentifier: 1,
            exitCode: 0,
            standardOutput: standardOutput,
            standardError: "",
            duration: .milliseconds(1),
            failureDescription: nil
        )
    }
}
