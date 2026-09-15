#!/usr/bin/env python3
"""Run real native-tool and built-in-skill logic tests without launching OmniBot.

Uses an isolated Swift package containing the production sources. No application,
simulator, screenshots, production data, or real Keychain items are accessed.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "AgentCore/Models/AgentValue.swift",
    "AgentCore/Models/AgentToolCall.swift",
    "AgentCore/Resources/AgentArtifact.swift",
    "AgentCore/Resources/AgentArtifactAction.swift",
    "AgentCore/Resources/AgentResourceProtocol.swift",
    "AgentCore/Workspace/WorkspacePaths.swift",
    "AgentCore/Workspace/WorkspacePathError.swift",
    "AgentCore/Workspace/AgentWorkspaceDescriptor.swift",
    "AgentCore/Workspace/SoulStore.swift",
    "AgentCore/Memory/MemoryPromptContext.swift",
    "AgentCore/Memory/MemorySearchHit.swift",
    "AgentCore/Memory/MemorySource.swift",
    "AgentCore/Prompt/AgentSystemPromptContext.swift",
    "AgentCore/Prompt/AgentSystemPromptBuilder.swift",
    "AgentCore/Tools/AgentToolExecutionContext.swift",
    "AgentCore/Tools/AgentToolExecutionResult.swift",
    "Tools/Core/OmniAgentToolError.swift",
    "Tools/Core/OmniToolArguments.swift",
    "Tools/FileSystem/WorkspaceDescriptorFileSystem.swift",
    "Tools/NativeTools/NativeToolAgentBridge.swift",
    "App/Settings/Skills/SkillSettingsModel.swift",
    "App/Settings/Skills/SkillSettingsAlert.swift",
    "App/NativeTools/NativeToolLibraryModel.swift",
    "Features/Chat/Composer/ChatComposerDraft.swift",
    "Features/Chat/Composer/ChatComposerSkillReference.swift",
    "Features/Chat/Composer/ChatComposerAvailability.swift",
]

REGRESSION_TESTS = [
    "TestSupport/Workspace/TemporaryWorkspace.swift",
    "TestSupport/Workspace/WorkspaceSymlinkFlipper.swift",
    "AgentCore/Skills/AgentSkillStoreTests.swift",
    "AgentCore/Prompt/AgentSystemPromptBuilderTests.swift",
    "App/Settings/Skills/SkillSettingsModelTests.swift",
    "Features/Chat/Composer/ChatComposerDraftTests.swift",
    "Features/Chat/Composer/ChatComposerAvailabilityTests.swift",
]


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="omnibot-native-tools-tests-") as directory:
        package = Path(directory)
        sources = package / "Sources" / "Via_Vera"
        tests = package / "Tests" / "NativeToolsTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        source_paths = [ROOT / "OmniBot" / name for name in SOURCES]
        source_paths += list((ROOT / "OmniBot/NativeTools").rglob("*.swift"))
        source_paths += list((ROOT / "OmniBot/AgentCore/Skills").glob("*.swift"))
        for source in source_paths:
            destination = sources / source.relative_to(ROOT / "OmniBot")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        for test in (ROOT / "OmniBotTests/NativeTools").glob("*.swift"):
            shutil.copy2(test, tests / test.name)
        for relative in REGRESSION_TESTS:
            test = ROOT / "OmniBotTests" / relative
            shutil.copy2(test, tests / test.name)
        (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "NativeToolsChecks",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "Via_Vera", swiftSettings: [
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ]),
        .testTarget(name: "NativeToolsTests", dependencies: ["Via_Vera"])
    ],
    swiftLanguageModes: [.v6]
)
''')
        environment = os.environ.copy()
        environment["OMNIBOT_NATIVE_TOOL_SKILL_DIRECTORY"] = str(
            ROOT / "OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder"
        )
        return subprocess.run(["xcrun", "swift", "test", "--package-path", str(package)], env=environment).returncode


if __name__ == "__main__":
    raise SystemExit(main())
