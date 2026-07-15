import Foundation
import Observation

@MainActor
@Observable
final class AlpineEnvironmentSettingsModel {
    private static let mirrorDefaultsKey = "alpine.packageMirror"

    var selectedMirror: AlpinePackageMirror
    private(set) var inventory: [String: AlpineEnvironmentInventoryItem] = [:]
    private(set) var selectedPackageIDs: Set<String> = []
    private(set) var operation: AlpineEnvironmentOperation = .idle
    private(set) var hasCompletedDetection = false
    private(set) var feedbackMessage: String?
    private(set) var feedbackIsError = false

    @ObservationIgnored
    private let commandRunner: any AlpineEnvironmentCommandRunning

    @ObservationIgnored
    private let userDefaults: UserDefaults

    init(
        commandRunner: any AlpineEnvironmentCommandRunning,
        userDefaults: UserDefaults = .standard
    ) {
        self.commandRunner = commandRunner
        self.userDefaults = userDefaults
        selectedMirror = userDefaults.string(forKey: Self.mirrorDefaultsKey)
            .flatMap(AlpinePackageMirror.init(rawValue:)) ?? .official
    }

    var isBusy: Bool {
        operation != .idle
    }

    var readyCount: Int {
        AlpineEnvironmentPackageDefinition.all.count { definition in
            inventory[definition.id]?.isReady == true
        }
    }

    var selectedMissingCount: Int {
        AlpineEnvironmentPackageDefinition.all.count { definition in
            selectedPackageIDs.contains(definition.id)
                && inventory[definition.id]?.isReady != true
        }
    }

    var allPackagesAreReady: Bool {
        readyCount == AlpineEnvironmentPackageDefinition.all.count
    }

    func refreshInventory(selectMissingByDefault: Bool = false) async {
        guard !isBusy else { return }
        operation = .detecting
        feedbackMessage = nil
        feedbackIsError = false

        let result = await commandRunner.runAlpineEnvironmentCommand(
            AlpineEnvironmentPackageDefinition.inventoryProbeCommand,
            timeout: .seconds(30)
        )
        let parsedInventory = AlpineEnvironmentInventoryItem.parse(result.standardOutput)
        if result.succeeded,
           parsedInventory.count == AlpineEnvironmentPackageDefinition.all.count {
            updateInventory(
                parsedInventory,
                selectMissingByDefault: selectMissingByDefault || !hasCompletedDetection
            )
            hasCompletedDetection = true
        } else {
            if !hasCompletedDetection {
                selectedPackageIDs = Set(AlpineEnvironmentPackageDefinition.all.map(\.id))
            }
            feedbackMessage = "检测 Alpine 环境失败：\(failureDetail(from: result))"
            feedbackIsError = true
        }
        operation = .idle
    }

    func togglePackageSelection(_ identifier: String) {
        guard !isBusy, inventory[identifier]?.isReady != true else { return }
        if selectedPackageIDs.contains(identifier) {
            selectedPackageIDs.remove(identifier)
        } else {
            selectedPackageIDs.insert(identifier)
        }
    }

    func installSelectedPackages() async {
        guard !isBusy else { return }
        let definitions = AlpineEnvironmentPackageDefinition.all.filter { definition in
            selectedPackageIDs.contains(definition.id)
                && inventory[definition.id]?.isReady != true
        }
        guard !definitions.isEmpty else {
            feedbackMessage = "没有需要安装的环境组件。"
            feedbackIsError = false
            return
        }

        operation = .installing
        feedbackMessage = nil
        feedbackIsError = false
        let result = await commandRunner.runAlpineEnvironmentCommand(
            AlpineEnvironmentPackageDefinition.installationScript(
                for: definitions,
                mirror: selectedMirror
            ),
            timeout: .seconds(15 * 60)
        )
        guard result.succeeded else {
            feedbackMessage = "环境配置失败：\(failureDetail(from: result))"
            feedbackIsError = true
            operation = .idle
            return
        }

        let probeResult = await commandRunner.runAlpineEnvironmentCommand(
            AlpineEnvironmentPackageDefinition.inventoryProbeCommand,
            timeout: .seconds(30)
        )
        let refreshedInventory = AlpineEnvironmentInventoryItem.parse(probeResult.standardOutput)
        guard probeResult.succeeded,
              refreshedInventory.count == AlpineEnvironmentPackageDefinition.all.count else {
            feedbackMessage = "安装已执行，但重新检测失败：\(failureDetail(from: probeResult))"
            feedbackIsError = true
            operation = .idle
            return
        }

        updateInventory(refreshedInventory, selectMissingByDefault: false)
        let remaining = definitions.filter { refreshedInventory[$0.id]?.isReady != true }
        if remaining.isEmpty {
            feedbackMessage = "环境配置完成，所选组件均已就绪。"
            feedbackIsError = false
        } else {
            feedbackMessage = "以下组件安装后仍未通过检测：\(remaining.map(\.title).joined(separator: "、"))"
            feedbackIsError = true
        }
        operation = .idle
    }

    func applySelectedMirror() async {
        userDefaults.set(selectedMirror.rawValue, forKey: Self.mirrorDefaultsKey)
        guard !isBusy else { return }
        operation = .applyingMirror
        _ = await commandRunner.runAlpineEnvironmentCommand(
            selectedMirror.repositorySetupCommand,
            timeout: .seconds(30)
        )
        operation = .idle
    }

    private func updateInventory(
        _ newInventory: [String: AlpineEnvironmentInventoryItem],
        selectMissingByDefault: Bool
    ) {
        inventory = newInventory
        let missingIDs = Set(AlpineEnvironmentPackageDefinition.all.compactMap { definition in
            newInventory[definition.id]?.isReady == true ? nil : definition.id
        })
        if selectMissingByDefault {
            selectedPackageIDs = missingIDs
        } else {
            selectedPackageIDs.formIntersection(missingIDs)
        }
    }

    private func failureDetail(from result: AlpineCommandResult) -> String {
        let detail = [
            result.failureDescription,
            result.standardError.trimmingCharacters(in: .whitespacesAndNewlines),
            result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        .compactMap { $0 }
        .first { !$0.isEmpty } ?? "请稍后重试。"
        return String(detail.suffix(500))
    }
}
