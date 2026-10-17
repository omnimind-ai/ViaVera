#!/usr/bin/env python3
"""Test shared chat memory against production sources without launching OmniBot."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
patterns = [
    "AgentCore/Memory/*.swift", "AgentCore/Models/*.swift",
    "AgentCore/Persistence/ConversationMode.swift",
    "AgentCore/Runtime/AgentChatCompleting.swift",
    "AgentCore/Workspace/WorkspacePaths.swift",
    "AgentCore/Workspace/WorkspacePathError.swift",
    "Tools/FileSystem/WorkspaceDescriptorFileSystem.swift",
    "Tools/Core/OmniAgentToolError.swift",
    "App/Settings/Memory/MemorySettingsModel.swift",
]
with tempfile.TemporaryDirectory(prefix="omnibot-chat-memory-") as directory:
    package = Path(directory)
    sources = package / "Sources/Via_Vera"
    tests = package / "Tests/ChatMemoryTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for pattern in patterns:
        for source in (repo / "OmniBot").glob(pattern):
            (sources / source.name).symlink_to(source)
    for pattern in ["AgentCore/Memory/*.swift", "TestSupport/Workspace/*.swift", "App/Settings/Memory/*.swift"]:
        for test in (repo / "OmniBotTests").glob(pattern):
            (tests / test.name).symlink_to(test)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "ChatMemoryChecks", platforms: [.macOS(.v26)],
    targets: [
        .target(name: "Via_Vera", swiftSettings: [
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ]),
        .testTarget(name: "ChatMemoryTests", dependencies: ["Via_Vera"], swiftSettings: [
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ])
    ], swiftLanguageModes: [.v6]
)
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "module-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "module-cache")
    result = subprocess.run([
        "xcrun", "swift", "test", "--disable-sandbox", "--package-path", str(package)
    ], cwd=repo, env=environment)
    raise SystemExit(result.returncode)
