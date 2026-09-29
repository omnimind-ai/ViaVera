# 后台执行与 iCloud 备份同步

入口：设置 → **备份与后台执行**。后台执行默认开启；iCloud 同步由用户在各设备开启。

## iOS 后台任务

参考 OpenMinis `4ef29002e88db1e20e462ec2ff46916e8a7dcb45` 的有限后台任务与静音音频组合，
在 Agent 任务、手动上下文压缩及同步期间持有任务租约。离开前台时启用 `.playback` 与
`.mixWithOthers`，完成或取消后释放。处理来电音频中断、媒体服务重置、路由变化和短暂前台切换。
激活失败最多重试三次；有限后台时间到期时，只有音频确实未运行才中断 Agent 任务。
进度沿用现有逐事件持久化与启动时中断恢复逻辑，不自动重放可能已产生副作用的工具。

这是延长后台执行的机制，不是 iOS 永久执行保证。用户强制退出、系统杀进程、资源压力或音频
会话被系统收回仍可能终止任务。macOS 不使用静音音频。该实现与 OpenMinis 一样依赖音频后台模式，
发布时需由发行方结合实际功能评估 Apple 后台模式审核要求。

## 同步范围与存储

- CloudKit 容器：`iCloud.omnimind.ocean.ViaVera`，私有数据库，自定义 zone `OmniBotSyncV1`。
- 记录类型：`OmniBotSyncItem`，字段 `payload` 为 Asset；不需要 query 索引。
- 聊天：保留会话和消息 UUID、内容、思考内容、工具调用与结果、上下文摘要、模型选择、置顶及用量。
- 配置：各模型服务的非秘密配置、默认模型、Soul、Memory Markdown、Skills 文件与启用注册表、外观及背景图。
- 文件：聊天附件、`.omnibot/shared` 分享文件和 `.omnibot/offloads` 生成文件。任意工作区文件、
  Alpine 根文件系统、浏览器会话、设备权限、闹钟和工具秘密存储不在范围内。
- API Key 和 endpoint binding 继续使用各设备的本地钥匙串，新设备需重新填写 API Key。

SwiftData 仍是本地数据库，显式设置 `cloudKitDatabase: .none`，无需迁移现有唯一约束和关系。
同步层导出可移植的版本数据，而不是复制打开中的 SQLite/WAL 文件。

应用启动、回到前台、任务完成和离开设置编辑页会触发同步；运行期间每 45 秒再检查一次。
同步仅在 Agent 空闲且未编辑其他设置时应用变更。应用被系统挂起或退出时不依赖轮询继续执行，
再次打开会追赶增量。当前没有静默推送唤醒。

## 数据保护与恢复

- 每次修改和删除都是不可变 UUID 版本，删除用 tombstone 表示。离线队列和 CloudKit 增量 token
  保存在 host-only `Control/CloudSync`；先落盘数据，再推进 token。重试不会重复生成相同版本。
- Lamport 计数器、设备 UUID 和版本 UUID 确定冲突顺序。保留所有冲突版本；同一会话同时编辑时
  选择一个完整会话版本，不把两个工具执行分支拼接。合并前、同步后均保留可恢复的检查点。
- 覆盖本地数据前重新比较内容摘要，拒绝覆盖扫描后产生的新编辑。工作区附件沿用 descriptor-relative
  文件访问，拒绝路径穿越、符号链接及非普通文件。
- 附件逐个读取、缓存和传输，不把整份附件库同时放入内存；未变化的文件复用已验证的内容摘要。
- 首次同步时，应用自动创建的默认 Soul 和空白 Memory 不参与覆盖旧设备内容。
- 每份数据限 64 MB。超限或损坏会显示错误并保留本机数据，不当作删除处理。
- 切换 iCloud 账户后暂停，需关闭再开启同步才能把本机数据同步到新账户；不会自动上传旧账户
  缓存中的远端历史。关闭同步不删除任一端的数据。
- 历史备份可分页查看和恢复。恢复会替换备份涉及的数据（含其删除状态），保留后来新增的其他
  内容；恢复前先保存当前版本。历史版本保存在云端，占用用户 iCloud 配额，当前不自动清理。

## Apple 开发者配置

1. iOS 和 macOS 使用同一个 bundle ID `omnimind.ocean.ViaVera`，在同一开发者团队启用 iCloud/CloudKit，
   并将两端 provisioning profile 关联到容器 `iCloud.omnimind.ocean.ViaVera`。工程 entitlements 已声明。
2. 在 CloudKit Console 的 Development 环境创建 `OmniBotSyncItem` 类型和 `payload: Asset` 字段，
   或由已签名的 Debug 版本首次成功同步创建。记录仅存储在用户私有数据库，不开放公共读取权限。
3. TestFlight/App Store 使用 Production 环境，发布前将 schema 从 Development 部署到 Production。
4. 两台设备登录同一 Apple 账户，开启 iCloud（使用 CloudKit accountStatus 检查，不依赖 iCloud Drive），
   在应用内分别开启同步。确认同步状态后再使用另一台设备编辑。

`CODE_SIGNING_ALLOWED=NO` 编译只能验证源码，不能证明 provisioning、Apple 账户或真实 CloudKit
服务可用。CloudKit 管理 CLI 需要独立的 management token；网页控制台无需此 token，
原生应用同步也不使用它。无需把 token 写入项目或聊天。

2026-09-29 本机检查：macOS 与 iOS 带签名构建均已通过，产物带有上述 CloudKit 容器 entitlement。
iOS 最初因 2026-07-14 的旧 profile 缺少 iCloud 权限而失败；命令行和后台 Xcode Service
同时报告 `No Accounts`，但用户的 Xcode 窗口已登录公司团队并具有 Admin 权限。
改由该窗口执行纯构建后，Xcode 于 2026-09-29 12:18:51 UTC 自动生成包含目标容器的
iOS development profile，构建成功。随后通过 `codesign --verify --deep --strict`，
并核对应用签名与内嵌 profile 的团队及容器权限。未启动应用。
因此，后台工具的 `No Accounts` 不能直接等同于用户未登录；遇到此情况先使用已登录的
Xcode 窗口刷新自动签名，不必删除账号或证书。
用户表示已完成 CloudKit 网页配置；生产 schema 部署和真实 iCloud 读写尚未独立验证。

## 验证命令

```sh
python3 Scripts/test-cloud-sync.py
xcodebuild -project OmniBot.xcodeproj -scheme OmniBot -configuration Debug \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project OmniBot.xcodeproj -scheme OmniBot -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

编译完整测试目标时使用 `-destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
和 `build-for-testing`，使测试架构与应用支持的 ARM64 保持一致；该命令不会启动应用。

测试脚本将实际同步、文件和 SwiftData 源码链接到临时 Swift Package，运行无界面单元测试，
不启动 OmniBot、不读取真实账号或真实聊天数据。真实设备的后台持续时间、来电干扰、锁屏和
跨设备 iCloud 往返需在签名与 schema 配好后验证。

本次无界面测试共 15 项，覆盖：摘要一致性、冲突收敛、删除防复活、路径范围、双设备完整会话与文件往返、
消息更新与唯一 ID、离线重试及重启、历史恢复、新账户隔离、忙碌期间暂停、网络等待中的编辑、
损坏负载拒绝、新设备默认值保护、云端 zone 重建，以及文件比较后写入与符号链接防护。
