#!/usr/bin/env python3
"""Run the real sync/persistence sources as headless Swift tests; never launch the app."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
sources = [
    "App/Sync/*.swift", "App/Background/*.swift",
    "App/Chat/ConversationRepository.swift", "App/Chat/PreferredModelStore.swift",
    "App/Chat/ChatCoordinatorError.swift", "AgentCore/Persistence/*.swift",
    "AgentCore/Models/*.swift", "AgentCore/Tools/AgentToolExecutionResult.swift",
    "AgentCore/Resources/AgentArtifact.swift", "AgentCore/Resources/AgentArtifactAction.swift",
    "AgentCore/Providers/Configuration/ProviderStore.swift",
    "AgentCore/Providers/Configuration/ProviderStoreError.swift",
    "AgentCore/Providers/Configuration/ProviderProfile.swift",
    "AgentCore/Providers/Configuration/ProviderProtocolType.swift",
    "AgentCore/Providers/Configuration/WireAPI.swift",
    "AgentCore/Providers/Discovery/ModelOption.swift",
    "AgentCore/Workspace/WorkspacePaths.swift", "AgentCore/Workspace/WorkspacePathError.swift",
    "AgentCore/Workspace/SoulStore.swift",
    "Tools/FileSystem/WorkspaceDescriptorFileSystem.swift", "Tools/Core/OmniAgentToolError.swift",
    "Features/Chat/ModelSelection/ProviderModelSelection.swift",
]

with tempfile.TemporaryDirectory(prefix="omnibot-sync-tests-") as temporary:
    package = Path(temporary)
    module = package / "Sources" / "Via_Vera"
    tests = package / "Tests" / "CloudSyncTests"
    module.mkdir(parents=True)
    tests.mkdir(parents=True)
    bridge = package / "Sources" / "OmniCloudKitBridge"
    (bridge / "include").mkdir(parents=True)
    (bridge / "include/OmniCloudKitContainer.h").symlink_to(repo / "OmniBot/App/Sync/OmniCloudKitContainer.h")
    (bridge / "OmniCloudKitContainer.m").symlink_to(repo / "OmniBot/App/Sync/OmniCloudKitContainer.m")
    for pattern in sources:
        for source in (repo / "OmniBot").glob(pattern):
            (module / source.name).symlink_to(source)
    (tests / "CloudSyncTests.swift").symlink_to(repo / "OmniBotTests/App/Sync/CloudSyncTests.swift")
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "OmniBotSyncHeadlessTests",
    platforms: [.macOS("26.4")],
    targets: [
        .target(name: "OmniCloudKitBridge", publicHeadersPath: "include"),
        .target(name: "Via_Vera", dependencies: ["OmniCloudKitBridge"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "CloudSyncTests", dependencies: ["Via_Vera"])
    ]
)
''')
    result = subprocess.run(["swift", "test", "--package-path", str(package)], cwd=repo)
    raise SystemExit(result.returncode)
