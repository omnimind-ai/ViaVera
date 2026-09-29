# OpenMinis background execution attribution

OmniBot's `App/Background/BackgroundExecutionController.swift` adapts the
background execution design and silent audio loop from OpenMinis:

- Source: https://github.com/OpenMinis/OpenMinis
- Reviewed revision: `4ef29002e88db1e20e462ec2ff46916e8a7dcb45`
- Original files: `src/ios/Agent/Background/BackgroundKeepAliveManager.swift`,
  `src/ios/Agent/Backup/BackupKeepAlive.swift`, and
  `src/ios/Agent/Chat/AIChatViewModel+BackgroundTask.swift`.
- License: GNU General Public License, version 3. The full GPLv3 text is
  included with OmniBot and at the repository root in `LICENSE`.
- Original project: OpenMinis and its contributors.

Modifications for OmniBot: task-scoped leases, Swift Observation, strict Swift
concurrency, lifecycle integration with ChatCoordinator, bounded activation
retries, and a macOS no-op implementation. No OpenMinis credentials, container
identifiers, location services, or telemetry are included.

The CloudKit synchronization implementation is specific to OmniBot's local
SwiftData and file storage. OpenMinis's cloud sync source was reviewed as a
reference; its database and synchronization engine are not embedded.
