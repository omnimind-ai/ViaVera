<h1 align="center">Via Vera</h1>

<h3 align="center">Your On-Device AI Assistant for Apple Platforms</h3>

<div align="center">
  <img alt="Apple platforms" src="https://img.shields.io/badge/platform-iOS%20%7C%20macOS-black?logo=apple">
  <a href="https://github.com/omnimind-ai/ViaVera/stargazers"><img alt="GitHub stars" src="https://badgen.net/github/stars/omnimind-ai/ViaVera"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--only-blue"></a>
  <br>
  <a href="https://omnimind.com.cn"><img src="https://img.shields.io/badge/About_us-万象智维-purple.svg?color=%234b0c77" alt="OmniMind"></a>
  <a href="https://linux.do"><img src="https://img.shields.io/badge/Linux_Do-Community-yellow.svg?color=%23ac3712" alt="Linux Do Community"></a>
  <a href="#community"><img src="https://img.shields.io/badge/WeChat-Group-lightgreen" alt="WeChat Group"></a>
</div>

<p align="center">
  <a href="#core-capabilities"><b>Capabilities</b></a>
  ·
  <a href="#quick-start"><b>Quick Start</b></a>
  ·
  <a href="#development-guide"><b>Development</b></a>
  ·
  <a href="https://github.com/omnimind-ai/ViaVera/issues"><b>Issues</b></a>
  ·
  <a href="#community"><b>Community</b></a>
</p>

> Via Vera is a native AI agent for iPhone, iPad, and Mac. Its agent runtime, tools, workspace, memory, and credentials remain under the control of the Apple device while it connects to the model provider chosen by the user.

Built with SwiftUI, Via Vera goes beyond chat by completing the full loop of **understand → decide → execute → reflect**. It combines a tool-calling agent with an embedded Alpine Linux environment, persistent memory, browser and workspace access, and native Apple integrations.

<h2 id="core-capabilities">Core Capabilities</h2>

- **Native Apple experience**: A shared SwiftUI app designed for iOS, iPadOS, and macOS.
- **Extensible agent tools**: Terminal, files, memory, skills, browser, calendar, contacts, alarms, and HealthKit.
- **Local Alpine environment**: An embedded ARM64 Alpine runtime powered by [`ish-arm64`](https://github.com/XuYouo/ish-arm64), with a controlled `/workspace` mount.
- **Flexible model providers**: OpenAI-compatible Chat Completions and Responses APIs, DeepSeek, and Anthropic Messages.
- **Persistent context**: SwiftData conversations, daily memory, long-term Markdown memory, local search, and configurable Soul instructions.
- **Security by design**: API keys are stored in Keychain, provider endpoints are validated, tool output is bounded, and sensitive response data is redacted.
- **Apple personal tools**: Permission-gated access to Calendar, Contacts, reminders, and HealthKit data.

<details open>
<summary id="quick-start"><strong>Quick Start</strong></summary>

### Get the code

```bash
git clone --recursive https://github.com/omnimind-ai/ViaVera.git
cd ViaVera
git submodule update --init --recursive
open OmniBot.xcodeproj
```

Select the `OmniBot` scheme in Xcode, choose an iOS Simulator or your Mac, and run the project. The installed app is named **Via Vera**.

### Configure the agent

1. Open **Settings → Model Service** and add a compatible provider, endpoint, and API key.
2. Select the models used by the agent.
3. Review the Soul, memory, skills, workspace, and permission settings.
4. Start a conversation and approve personal-data permissions only when the corresponding tools are needed.

On first launch, Via Vera imports its bundled Alpine minirootfs into Application Support. The model-accessible Alpine environment only mounts the shared workspace; provider configuration, Keychain credentials, Soul, and memory remain host-controlled.

<h2 id="use-cases">Use Cases</h2>

### Agent workflows

Ask Via Vera to break down a task, use multiple tools, inspect the result, and continue until the requested outcome is reached.

### Skills

Import Apple-compatible `SKILL.md` packages, enable or disable them in Settings, and let the agent load focused instructions when a request matches. A community skill collection is available at [OpenMinis/MinisSkills](https://github.com/OpenMinis/MinisSkills).

### Terminal and workspace

Run commands in the local Alpine environment, maintain logical terminal sessions, and read, write, search, or organize files inside the controlled workspace.

### Browser and personal tools

Use the browser tool for web tasks and, after explicit system permission, work with Calendar, Contacts, reminders, and supported HealthKit records.

</details>

<h2 id="development-guide">Development Guide</h2>

### Requirements

- Apple Silicon Mac
- Xcode with the iOS and macOS 26.4 SDKs
- Git with submodule support

The iSH core build script creates an isolated Python environment and installs its pinned Meson and Ninja tooling when required.

### Build without code signing

```bash
git submodule update --init --recursive

xcodebuild -project OmniBot.xcodeproj -scheme OmniBot \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project OmniBot.xcodeproj -scheme OmniBot \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

### Project layout

```text
OmniBot/
├── AgentCore/       # Models, providers, agent runtime, persistence, memory, skills, and security
├── Alpine/          # Swift and Objective-C bridge for the embedded iSH runtime
├── App/             # Application bootstrap, navigation, settings, and state coordination
├── Features/        # SwiftUI chat, terminal, settings, and sidebar presentation
├── Tools/           # Browser, filesystem, memory, personal, skills, and terminal tools
└── Resources/       # Alpine, terminal frontend, and legal resources

Vendor/ish-arm64/    # Pinned iSH ARM64 submodule
RuntimeSupport/      # Reproducible ARM64 guest runtime support
```

See [`Docs/ProjectStructure.md`](Docs/ProjectStructure.md) for module boundaries and contribution guidance.

<h2 id="privacy-and-security">Privacy and Security</h2>

- API keys are stored in Apple Keychain rather than provider JSON files.
- Provider credentials are bound to the normalized endpoint and protocol configuration.
- Non-loopback model endpoints must use HTTPS.
- Tool calls, provider responses, memory files, and imported skills have explicit size limits.
- Personal tools require Apple platform permissions and are only available on supported devices.
- Local Xcode user data, signing certificates, provisioning profiles, App Store Connect keys, and Codex workspace state are excluded from Git.

Please report security issues privately to the maintainers instead of opening a public issue containing credentials or personal data.

<h2 id="community">Community</h2>

Thanks to every community contributor, including developers from [linux.do](https://linux.do), who support the OmniBot ecosystem.

<table align="center">
  <tr>
    <td align="center">
      <img src="Docs/pic/wechat.jpg" alt="WeChat Group" width="220"><br>
      WeChat Group
    </td>
  </tr>
</table>

Join Discord: https://discord.gg/WnBvBXgykD

Special thanks to these open-source projects and communities:

- [`ish-app/ish`](https://github.com/ish-app/ish)
- [`XuYouo/ish-arm64`](https://github.com/XuYouo/ish-arm64)
- [Alpine Linux](https://alpinelinux.org)
- [OpenMinis](https://github.com/OpenMinis)

<h2 id="license">License</h2>

Via Vera's original source code is licensed under [`GPL-3.0-only`](LICENSE). Third-party components and bundled resources remain under their respective licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for attribution and distribution obligations.
