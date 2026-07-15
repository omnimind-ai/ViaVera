import Foundation

struct AlpineEnvironmentPackageDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let groupTitle: String
    let availabilityCommand: String
    let versionCommand: String
    let installationPackages: [String]

    static let all: [AlpineEnvironmentPackageDefinition] = [
        AlpineEnvironmentPackageDefinition(
            id: "nodejs",
            title: "nodejs",
            detail: "Node.js 运行时",
            groupTitle: "开发环境",
            availabilityCommand: "command -v node >/dev/null 2>&1 && node -e 'process.cwd()' >/dev/null 2>&1",
            versionCommand: "node --version",
            installationPackages: ["nodejs", "npm"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "npm",
            title: "npm",
            detail: "Node.js 包管理器",
            groupTitle: "开发环境",
            availabilityCommand: "command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1",
            versionCommand: "npm --version",
            installationPackages: ["npm"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "git",
            title: "git",
            detail: "Git 版本控制",
            groupTitle: "开发环境",
            availabilityCommand: "command -v git >/dev/null 2>&1",
            versionCommand: "git --version",
            installationPackages: ["git"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "python",
            title: "python",
            detail: "Python 解释器",
            groupTitle: "开发环境",
            availabilityCommand: "command -v python3 >/dev/null 2>&1",
            versionCommand: "python3 --version",
            installationPackages: ["python3"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "uv",
            title: "uv",
            detail: "Python 项目与包工具",
            groupTitle: "开发环境",
            availabilityCommand: "command -v uv >/dev/null 2>&1",
            versionCommand: "uv --version",
            installationPackages: ["python3", "py3-pip"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "pip",
            title: "pip",
            detail: "Python 包安装器",
            groupTitle: "开发环境",
            availabilityCommand: "command -v pip3 >/dev/null 2>&1",
            versionCommand: "pip3 --version",
            installationPackages: ["py3-pip"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "ssh_client",
            title: "ssh",
            detail: "SSH 客户端",
            groupTitle: "SSH",
            availabilityCommand: "command -v ssh >/dev/null 2>&1",
            versionCommand: "ssh -V",
            installationPackages: ["openssh-client-default"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "sshpass",
            title: "sshpass",
            detail: "SSH 密码辅助工具",
            groupTitle: "SSH",
            availabilityCommand: "command -v sshpass >/dev/null 2>&1",
            versionCommand: "sshpass -V",
            installationPackages: ["sshpass"]
        ),
        AlpineEnvironmentPackageDefinition(
            id: "openssh_server",
            title: "sshd",
            detail: "OpenSSH 服务器",
            groupTitle: "SSH",
            availabilityCommand: "command -v sshd >/dev/null 2>&1",
            versionCommand: "sshd -V",
            installationPackages: ["openssh-server"]
        ),
    ]

    static var groupTitles: [String] {
        all.reduce(into: []) { result, definition in
            if !result.contains(definition.groupTitle) {
                result.append(definition.groupTitle)
            }
        }
    }

    static var inventoryProbeCommand: String {
        all.map { definition in
            """
            if \(definition.availabilityCommand); then
              version="$(\(definition.versionCommand) 2>&1 | head -n 1 | tr '\\r\\t' '  ')"
              printf '__OMNI_ENV__\\t%s\\tREADY\\t%s\\n' '\(definition.id)' "$version"
            else
              printf '__OMNI_ENV__\\t%s\\tMISSING\\t\\n' '\(definition.id)'
            fi
            """
        }
        .joined(separator: "\n")
    }

    static func installationScript(
        for definitions: [AlpineEnvironmentPackageDefinition],
        mirror: AlpinePackageMirror
    ) -> String {
        var packages: [String] = []
        for package in definitions.flatMap(\.installationPackages) where !packages.contains(package) {
            packages.append(package)
        }

        var commands = [mirror.repositorySetupCommand]
        if !packages.isEmpty {
            commands.append("apk add --no-cache \(packages.joined(separator: " "))")
        }

        let identifiers = Set(definitions.map(\.id))
        if !identifiers.isDisjoint(with: ["python", "pip", "uv"]) {
            commands.append("ln -sf /usr/bin/python3 /usr/local/bin/python || true")
        }
        if !identifiers.isDisjoint(with: ["pip", "uv"]) {
            commands.append("ln -sf /usr/bin/pip3 /usr/local/bin/pip || true")
        }
        if identifiers.contains("uv") {
            commands.append("if ! apk add --no-cache uv; then python3 -m pip install --break-system-packages --upgrade uv; fi")
        }
        if identifiers.contains("openssh_server") {
            commands.append("mkdir -p /var/run/sshd /etc/ssh")
            commands.append("ssh-keygen -A || true")
        }

        return commands.joined(separator: "\n")
    }
}
