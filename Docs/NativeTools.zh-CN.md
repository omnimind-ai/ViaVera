# 原生小工具

## 使用入口

iPhone 首页通过「聊天 / 工具」底部标签切换。工具页面支持 AI 制作、收藏、搜索和 JSON 工具包导入；打开工具后可以让 AI 修改、导出源码包或恢复上一版界面与逻辑。macOS 从侧边栏「我的工具」进入同一套原生界面。

进入聊天详情后隐藏底部根标签栏，返回聊天列表时重新显示。工具列表不显示页面标题；点击添加或「用 AI 制作」直接进入正常聊天，在输入框中预先引用 `native-tool-builder`，以浅蓝色胶囊显示。用户自行描述需求后发送，也可移除引用；「让 AI 修改」沿用相同入口并携带当前工具 ID。

「两步认证」默认作为内置工具安装，直接进入工具列表即可使用，无需配置模型或先让 AI 生成。它与 AI 制作的工具使用同一份 JSON 协议、校验、原生渲染及存储流程。支持收藏、修改和删除；删除后重启不会自动恢复。需要再次体验时，在工具列表右上角「工具操作 → 恢复内置工具」重新添加。

内置工具安装历史保存在宿主工具目录的 `.built-in-tools.json`，首次升级到此版本也会添加默认工具。重复加载不会生成副本或覆盖用户修改；手动恢复仅添加缺失的工具，并使用新的 UUID，已删除的验证码账户不会随工具恢复。

「Skills → 内置 → 原生工具制作」默认启用。停用后不再进入 Agent 的 Skills 索引；用户导入的 Skills 与内置 Skills 使用同一套启停机制。内置内容来自应用资源包，不能由工作区文件覆盖或从设置页删除。

## 制作协议

内置说明与示例位于 [native-tool-builder](../OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder/SKILL.md)，完整协议见 [package-format.md](../OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder/references/package-format.md)。

Agent 调用链：

1. `skills_read` 读取制作 Skill，并按需读取协议和模板。
   使用原生能力前，通过 `native_tool_capabilities` 查询操作名、参数、权限和结果结构。
2. `file_write` 写出 JSON 草稿。
3. `native_tool_validate` 校验组件、状态、表达式、动作及容量限制。
4. `native_tool_install` 安装，或使用 `tool_id` 和 `expected_revision` 更新现有工具。
5. 返回安装结果中的 `openURL`，用户可直接打开。

`native_tool_list` 列出工具元信息；`native_tool_read` 返回已安装源码与版本，供后续修改。两者均不返回用户运行数据或认证凭据。

## 运行与数据

- JSON 界面树由 `NativeToolComponentView` 映射为 SwiftUI 组件。
- `NativeToolExpression` 执行有深度、体积限制的表达式；`NativeToolActionEngine` 事务执行状态与集合动作。
- `NativeToolRuntime` 持有页面状态，并串行保存用户操作。
- `NativeToolCapabilityRegistry` 是统一能力目录，Agent 查询、包校验和宿主调用授权共用这份定义。JSON 用 `invoke` 指定操作、参数表达式及结果位置。
- `NativeToolHostCapabilities` 为每个工具提供同一套相机、图片、文件、剪贴板、确认对话框和 OTP 服务；不根据内置标记或特定工具 UUID 提供特殊功能。
- `sessionState` 保存仅本次运行使用的结果和输入；`secureField` 只能通过 `sessionBinding` 绑定这里。它不落盘、不返回给 Agent，退出/锁定时清除。文件内容使用本会话内的句柄传递。
- `NativeToolStore` 在宿主专属 Control 目录保存源码版本和工具数据，与 Agent 的共享工作区隔离。
- 工具身份由宿主分配。更新保留已有状态并保存上一版源码；版本冲突或数据类型变化会被拒绝。恢复上一版保留当前数据。
- 导入预览使用内存状态；导出的工具包只包含源码和初始值，不包含运行数据。

首版提供基础布局、文本与数值输入、开关、选择器、列表、计算、条件、集合操作、多页面和前台倒计时。新增系统能力或原生组件需要更新宿主；任意脚本、网络请求和后台任务不在首版协议中。

## 两步认证

TOTP 由 [totp.json](../OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder/assets/totp.json) 完整定义界面和操作流程，使用普通输入框、列表、按钮、进度组件调用 `otp.*`、`camera.*`、`files.*` 等公共能力。已移除 TOTP 专属 Swift 管理页；Swift 只实现通用渲染器、系统交互和能力服务。二维码读取器 [qr-reader.json](../OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder/assets/qr-reader.json) 复用相同相机和剪贴板接口。

账户按工具 UUID 存入独立 Keychain 命名空间。OTP 服务返回账户显示信息、短期验证码与有效期供 JSON 页面渲染；这些结果只在 sessionState 中。长期密钥和待确认的导入账户由宿主保管，不出现在 Agent 接口。旧版 `totp` 组件工具在读取时迁移为公共能力包，保留工具 UUID、现有状态与 Keychain 命名空间；新包不能再使用整体 `totp` 组件。

支持 Base32 / otpauth 输入、二维码图片导入、SHA1 / SHA256 / SHA512、6 / 8 位验证码，以及带密码的加密备份恢复。备份使用 PBKDF2-HMAC-SHA256 和 AES-GCM；TOTP 实现以 [RFC 6238 Appendix B](https://www.rfc-editor.org/rfc/rfc6238.html#appendix-B) 向量验证。iOS 剪贴板限制在本机并设定过期时间；macOS 仅在剪贴板仍为本次写入时自动清除。

添加账户还支持相机直接扫码和 TXT 批量导入：

- 点击「扫描二维码」后使用系统相机识别一个 `otpauth://totp/` 认证二维码，随后预览账户并确认导入。
- 点击「从 TXT 文件批量导入」，每行填写一条完整的 `otpauth://totp/` 链接。支持 UTF-8（含 BOM）及带 BOM 的 UTF-16、空行、首尾空白、Windows / Unix 换行；文件最多 1 MB、1,000 条链接。
- 批量导入先完整校验并预览。无效行会指出实际行号，整批不保存；重复账户自动跳过，保存后显示新增和重复数量。每个工具最多保存 200 个账户。
- 扫码使用 [AVFoundation 元数据采集](https://developer.apple.com/documentation/avfoundation/avcapturemetadataoutput)，采集配置、启动和停止运行在专用串行队列。仅在用户打开扫码时申请相机权限；不录制照片或视频。页面退出、账户锁定或应用进入后台后停止采集。

能力调用参数与数据生命周期见 [capabilities.md](../OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder/references/capabilities.md)。纯数据动作保持事务语义；含原生调用的动作顺序执行，失败后停止后续步骤，已经完成的系统操作不会被撤回。

## 验证

在仓库根目录执行：

```sh
python3 Scripts/test-native-tools.py
```

脚本将实际生产代码和相关测试复制到临时 Swift Package，运行新功能、Skills 和提示词回归测试，不启动 OmniBot，不访问真实 Keychain 记录，也不截图。原生导航与平台集成通过 Xcode 编译检查；实际界面、设备身份验证、二维码选择与文件分享仍需真机验收。
