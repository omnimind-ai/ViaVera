# OmniBot project structure

OmniBot keeps top-level technical boundaries, then groups files by capability inside
each boundary. This makes a feature easy to locate without mixing UI, application state,
domain contracts, and side-effecting implementations in one directory.

## Source layout

```text
OmniBot/
├── App/
│   ├── Bootstrap/             # App entry point, dependency assembly, root model
│   ├── Navigation/            # Root destinations
│   ├── Chat/                  # Conversation repository and chat coordination
│   ├── Runtime/               # Alpine and interactive-terminal application state
│   └── Settings/              # Settings state grouped by capability
├── AgentCore/
│   ├── Providers/
│   │   ├── Clients/           # Provider-specific HTTP and wire implementations
│   │   ├── Configuration/     # Profiles, endpoints, protocols, and persistence
│   │   ├── Discovery/         # Model discovery and models.dev catalog
│   │   └── Reasoning/         # Provider reasoning parsing
│   └── ...                    # Agent domain models, runtime, memory, workspace
├── Features/
│   ├── Chat/                  # Composer, transcript, Markdown, tools, usage
│   ├── Runtime/               # Alpine environment and interactive terminal UI
│   ├── Settings/              # Settings shell, shared controls, capability pages
│   └── Sidebar/               # Conversation navigation UI
├── Tools/
│   ├── Core/                  # Executor, schemas, arguments, limits, shared helpers
│   ├── Browser/
│   ├── FileSystem/
│   ├── Memory/
│   ├── Personal/              # Alarm, calendar, contacts, shared parsing/errors
│   ├── Skills/
│   └── Terminal/
├── Alpine/                    # iSH bridge and Alpine runtime implementation
└── Resources/
```

`AgentCore/Tools` contains the tool execution protocol and transport types. Concrete
Apple and Alpine-backed implementations belong in `OmniBot/Tools`. The shared
`WorkspaceDescriptorFileSystem` currently remains in `Tools/FileSystem`; moving it
across the boundary requires a separate dependency and error-model refactor.

## Placement rules

1. Put SwiftUI views and presentation-only models under the relevant `Features` capability.
2. Put app-owned observable state, coordinators, repositories, and bootstrap wiring under
   the matching `App` capability.
3. Put provider-independent agent rules, data contracts, persistence records, and runtime
   policies under `AgentCore`.
4. Put concrete system integrations and model-callable side effects under the matching
   `Tools` capability. Keep execution protocols in `AgentCore/Tools`.
5. Mirror production capabilities under `OmniBotTests`. Shared test helpers belong in
   `OmniBotTests/TestSupport` rather than under a feature that happens to use them first.

The Xcode project uses filesystem-synchronized groups for the app and test roots. Moving
files inside `OmniBot`, `OmniBotTests`, or `OmniBotUITests` normally requires no manual
`project.pbxproj` edits, but moving a file across those roots changes target membership.

## Path-sensitive areas

Do not reorganize these paths as part of routine feature cleanup:

- `OmniBot/Info.plist`
- `OmniBot/OmniBot.entitlements`
- `OmniBot/OmniBot-Bridging-Header.h`
- `OmniBot/Alpine/OmniISHRuntime.h`
- `Scripts`, `RuntimeSupport`, and `Vendor`

They are referenced directly by Xcode build settings, the bridging header, or the iSH
build pipeline and should be moved only in a dedicated, fully validated change.
