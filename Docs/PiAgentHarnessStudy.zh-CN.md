# Pi Agent Harness 研究与 Apple 端落地

研究基线：`earendil-works/pi`，提交 `5cd93f688aaab89dbb6dfa4aca535f21796ae185`（2026-08-20）。对照实现：Android `/Users/ocean/code/OmnibotApp`；落地目标：当前 iOS/macOS Agent 模式。

## 结论

Pi 的“自进化”不是运行时修改模型权重，而是让 Agent 持续读写一组可审计、可版本化的外部资产：session tree、context files、skills、extensions 和 memory。真正有价值的是 harness 对上下文、工具副作用和恢复语义的约束。

Pi 仓库需要区分两层：

- 已运行的 coding-agent 机制：JSONL 会话树、分支、compaction entry、按需 skill 读取、扩展 hook，以及 provider 边界的 context transform。
- `packages/agent/docs/harness.md` 描述的 durable harness v2：immutable entry tree、namespaced registers、append-only usage ledger、lane/op program counter，以及工具调用的 intent/effect/settlement 三段式事务。

后者仍不是完整生产实现。仓库测试仍把对应表面称为 `AgentHarness v2 scaffold`，并对未完成操作断言 `HarnessNotImplemented`。因此 Apple 端只移植已经能用独立测试证明的语义，不照搬尚未完成的存储 API。

## 与 Android 和原 Apple 端的差异

| 能力 | Pi / Android 参考 | Apple 改造前 | 本次 Apple 落地 |
|---|---|---|---|
| Memory | 索引/搜索后按需读取 | 每轮自动注入长期、当天及检索正文 | 正文不自动注入，使用 `memory_search` / `memory_load` |
| Skills | 稳定索引，`SKILL.md` 按需读取 | 自动匹配并注入最多两份正文 | 只注入排序索引，使用 `skills_read` |
| 时间 | 粗粒度缓存 + 精确时间工具 | 5 分钟缓存的精确分钟写入 prompt | 1 小时粗粒度日期缓存 + `context_time_now` |
| Context | 自适应 reserve、结构化压缩、溢出恢复一次 | 只支持手动压缩 | 接近阈值自动压缩；确认是 provider context overflow 后最多压缩重试一次 |
| Tool durability | intent commit → effect → settlement commit | 先保存 assistant tool call，effect 后才保存 tool result | effect 前保存 pending tool intent；settlement 覆盖同一记录 |
| Crash recovery | never-replay 操作恢复为 unknown | 缺失结果由 history window 临时修复 | pending intent 持久恢复为 interrupted / outcome unknown |
| Prompt cache | 稳定 session key、确定性前缀；Android 有 Anthropic 断点 | 无稳定 cache key；Anthropic 未启用断点；usage 口径混乱 | 会话级匿名 key、稳定 tool/JSON 顺序、Anthropic 三段断点、兼容回退 |
| Tool result | Android 12 KiB 模型视图并保留 artifact；Pi 保留 call-id 事务 | 单次 32 KiB、只保留头部 | 单次 12 KiB、保留头尾和 artifact；截断调用拒绝执行并回传同 call-id 错误 |
| 自进化经验 | 外部可审计资产 | 没有自动失败经验账本 | 有界、去重、脱敏的 `HARNESS_ERRORS.md`，可被 memory 工具检索 |

## 缓存计量约定

Apple 端在 provider 边界统一成下面的内部口径，避免 UI 对 OpenAI 重复计算、或把 Anthropic 缓存写入误报为命中：

- `promptTokens`：未从缓存读取的输入；包含本次缓存写入。
- `cachedTokens`：本次从缓存读取的输入。
- `cacheCreationTokens`：本次新写入缓存的输入，是 `promptTokens` 的子集。
- `contextTokens`：`promptTokens + cachedTokens`。
- 缓存命中率：`cachedTokens / contextTokens`；只有 provider 明确返回缓存明细时才显示。

缓存胶囊显示 `hit:<百分比>`，存在写入时额外显示 `write:<token>`。这能区分“首次写入所以命中为 0”和“provider 根本没有返回缓存指标”。

## 落地边界

1. 不自动重放结果未知的工具调用。文件写入、终端命令、日历、联系人等都可能已有外部副作用；恢复后必须先检查状态。
2. 溢出分类只接受 provider 的结构化 HTTP 错误，并排除 rate limit / throttling，避免把 429 当成长上下文问题。
3. 自动压缩使用 Android 已验证的自适应 reserve：容量的 `1/8`，限制在 `2,048...16,384`，且不超过容量一半。
4. 失败经验只记录工具名、运行 ID、脱敏摘要、重复次数和时间；最多保留 80 条，文件上限 256 KiB。它是运行经验，不是隐式用户偏好。
5. 保留现有 SOUL、结构化 compaction summary、会话顺序修复、工具结果预算和 Apple 原生权限边界。

## 后续演进建议

当前实现先完成了 durable harness 的最小闭环。若继续演进，优先顺序应是：

1. 为 tool checkpoint 增加显式 replay policy（safe replay / never replay），而不是仅按工具类别保守处理。
2. 把 compaction checkpoint 变成自包含 entry，减少对旧会话记录的隐式依赖。
3. 为 memory/skill 读取增加观测指标：命中率、读取成本、失败经验复用率；用数据判断 progressive disclosure 是否改善任务成功率。
4. 等 Pi v2 从 scaffold 变为实现后，再评估 registers、usage ledger 和 lane/op program counter，避免现在引入一套尚不稳定的存储抽象。
