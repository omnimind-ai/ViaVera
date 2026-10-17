#!/usr/bin/env python3
"""Run chat runtime regressions against production sources without launching the app."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
patterns = [
    'AgentCore/Models/*.swift', 'AgentCore/Runtime/*.swift',
    'AgentCore/Tools/*.swift', 'AgentCore/Resources/AgentArtifact.swift',
    'AgentCore/Resources/AgentArtifactAction.swift',
    'AgentCore/Providers/Clients/OpenAI/OpenAICompatibleClientError.swift',
    'AgentCore/Providers/Configuration/WireAPI.swift',
    'AgentCore/Persistence/ConversationMode.swift',
    'Tools/Core/OmniAgentToolDefinitions.swift',
    'Tools/NativeTools/OmniAgentToolDefinitions+NativeTools.swift',
]
with tempfile.TemporaryDirectory(prefix='omnibot-chat-runtime-') as directory:
    package = Path(directory)
    sources = package / 'Sources/Via_Vera'
    tests = package / 'Tests/ChatRuntimeTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for pattern in patterns:
        for source in (repo / 'OmniBot').glob(pattern):
            (sources / source.name).symlink_to(source)
    for name in ['AgentRunnerTests.swift', 'AgentHarnessPolicyTests.swift', 'AgentReasoningStreamingTests.swift']:
        (tests / name).symlink_to(repo / 'OmniBotTests/AgentCore/Runtime' / name)
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "ChatRuntimeChecks", platforms: [.macOS(.v26)],
    targets: [
        .target(name: "Via_Vera", swiftSettings: [
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ]),
        .testTarget(name: "ChatRuntimeTests", dependencies: ["Via_Vera"], swiftSettings: [
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ])
    ], swiftLanguageModes: [.v6]
)
''')
    environment = os.environ.copy()
    environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'module-cache')
    environment['SWIFT_MODULECACHE_PATH'] = str(package / 'module-cache')
    result = subprocess.run([
        'xcrun', 'swift', 'test', '--disable-sandbox', '--package-path', str(package)
    ], cwd=repo, env=environment)
    raise SystemExit(result.returncode)
