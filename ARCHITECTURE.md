# 微信 iOS 越狱候选回复插件架构书

**状态**：V1 实施基线  
**日期**：2026-09-29  
**目标读者**：iOS Tweak 开发者、模型接入开发者、测试与安全审查人员

## 1. 目标与边界

本项目在用户本人使用的越狱 iPhone 上，为微信聊天页提供“读取当前会话上下文 → 结构化判断 → 生成 2～3 条候选回复 → 用户点选后填入微信原生输入框”的辅助流程。插件不得触发发送动作；消息发送始终由用户在微信原生界面手动完成。

V1 仅处理用户当前打开的单个聊天会话。默认只处理可读取的文字消息；图片、语音、文件、位置等以类型占位，不做 OCR、转写、下载或上传。群聊可在适配层验证后支持，但必须标明发送者，无法可靠区分发送者时关闭该会话的生成功能。不处理后台会话、通讯录遍历、批量生成、自动回复、定时回复或无人值守触发。

用户主动点击“生成”才会构造上下文并调用模型。首次使用远程 Provider 前，界面必须明确说明“哪些聊天内容将发送给哪个服务”，取得开启选择；之后可随时关闭。插件默认关闭远程传输和聊天内容持久化。

### 1.1 V1 验收口径

1. 已验证的微信版本中，进入聊天页后能识别当前会话；点击生成后显示 2～3 条候选回复。
2. 点击候选项只将文本写入当前微信输入框，保持未发送状态；用户原有草稿非空时先提示覆盖或取消。
3. 切换会话、页面离开、消息变化或用户修改输入框时，旧结果不可再填入；过期请求可取消或丢弃。
4. 未获远程传输许可时不发起网络请求；日志和崩溃材料不包含消息正文、联系人标识和密钥。
5. 未知微信版本、Hook 校验失败或输入框定位失败时安全关闭对应功能，微信原有聊天与发送行为保持正常。
6. 对无障碍设置（动态字体、深色模式）及网络失败、模型超时、空结果完成设备验收。

## 2. 架构原则与整体流程

微信私有对象只在 `WeChatAdapter` 中出现。其余模块只看稳定的内部 DTO。所有影响微信 UI 的操作回到主线程；网络与模型计算不得阻塞主线程。每次生成绑定会话 ID、页面实例、消息快照哈希和请求 ID，用于阻止串会话与过期草稿。

```text
用户点击生成
    ↓
ReplyOverlay → SessionCoordinator
    ↓
WeChatAdapter → MessageAdapter → ContextEngine → PrivacyGate
                                                ↓
                                     DecisionEngine (JEV/Laya/规则)
                                                ↓
                                     GenerationEngine (文本生成 Provider)
                                                ↓
                             CandidateValidator → ReplyOverlay
                                                ↓ 用户点选
                         WeChatAdapter.fillDraft(仅填入，不发送)
```

`SessionCoordinator` 是唯一流程编排者；各引擎不得直接调用微信私有 API。`PrivacyGate` 在调用远程服务前执行许可与内容过滤。模型输出都视为不可信文本，经过结构校验与候选校验后才能显示。

## 3. 模块职责

| 模块 | 输入与职责 | 输出与禁区 |
| --- | --- | --- |
| Tweak Bootstrap | 限定微信进程加载、读取适配清单、注册 Hook、启动开关 | 不主动扫描聊天数据；失败时禁用插件 |
| WeChatAdapter | 识别当前聊天页、会话标识、可见消息和原生输入框；提供填草稿能力 | 唯一接触微信私有类/Selector/字段的模块；不得暴露发送能力 |
| MessageAdapter | 将微信消息对象转成内部 `ChatMessage`；排序、去重、校验发送者 | 不保存原始微信对象；不读取非当前会话 |
| ContextEngine | 按时间及 token/字符预算截取最近 N 条；标识媒体占位与上下文不完整 | `ContextSnapshot`；不擅自补充或猜测媒体内容 |
| PrivacyGate | 检查许可、远程目标、敏感字段规则和请求范围 | 允许/阻断/要求用户确认；不得静默上传 |
| DecisionEngine | 对意图、语气、是否适合回复、风险和策略做限定值判断 | `DecisionResult`；不得直接写草稿或控制微信 |
| GenerationEngine | 根据快照与决策，生成 2～3 条短回复 | `Candidate[]`；不得发送消息 |
| ReplyOverlay | 显示状态、候选、错误和许可；响应用户点击 | 不模拟微信发送按钮 |
| ProviderRegistry | 决策与生成 Provider 的选择、超时、取消和错误映射 | 对上层暴露内部协议；具体服务协议只在适配器中 |
| Config/Telemetry | 保存非敏感设置、结构化诊断指标 | 密钥用系统安全存储；日志不得包含聊天正文 |

### 3.1 Tweak 与适配层

建议使用 Theos + Logos/Objective-C（或 Objective-C++）实现最薄的进程注入层。构建目标、rootless/rootful 打包方案须与实际测试设备和越狱环境匹配；V1 优先选择一组明确可测试的设备、iOS、越狱及微信版本，不声称“通用兼容”。Theos 的 [Logos 文档](https://theos.dev/docs/logos-syntax)说明 Hook 语法；[rootless 文档](https://theos.dev/docs/rootless)说明其打包方案。

适配层分三部分：`ChatPageProbe`（页面和会话识别）、`MessageProbe`（当前页面消息读取）、`DraftWriter`（原生输入框定位与填入）。优先在聊天页生命周期和现有消息数据更新路径建立只读观察，再在用户点击时抓取快照。Hook 中只做轻量判定并调用原实现；禁止同步网络请求、复杂模型计算、全局消息数据库遍历。对任何内部对象做类型、空值和生命周期检查。

`DraftWriter` 的公开接口仅有 `fillDraft(text, expectedSession, expectedPage, expectedSnapshot)`，无 `send`/`tapSend`。填入前检查页面仍可见、会话未变、输入框可编辑、草稿状态符合用户选择；填入后触发微信原生文本变更机制并再次确认显示值。实现需遵循已验证版本的控件行为，不能假定直接设置 `text` 就足够。

### 3.2 Message Adapter 与 Context Engine

只读取当前会话最近的有限消息。统一 `direction`、`senderId`、时间、类型和文本；同一消息多次 UI 更新时按稳定 ID 去重。内部消息 ID 仅在本次内存会话中使用，跨进程或远程请求不传微信原始 ID。排序优先使用微信消息时间与稳定序号，异常顺序标记 `partial=true`。撤回、删除、系统提示、引用消息分别标记；引用内容仅在确认可见、确属当前会话时纳入。

上下文预算设为配置项，默认最近 20 条且不超过生成 Provider 的安全输入预算；截断从最旧消息开始，始终保留最后一条用户可见消息。群聊中每条必须附发送者的会话内匿名标签。图片和语音使用如 `[图片，内容未读取]` 的占位；不推断内容。`ContextSnapshot` 生成时计算哈希，消息增加或会话切换后失效。

### 3.3 Decision Engine：JEV/Laya

JEV 与 Laya 在本架构中只提供 **限定集合的判断**，例如 `replyNeed`、`intent`、`tone`、`risk`、`strategy`。它们不是候选回复文本生成器。TypeSafe AI 的 [JEV Quick start](https://docs.typesafe.ai/introduction/quickstart)描述 `choice`、`score`、`noul` 类型；Laya 项目的[源码仓库](https://github.com/NandhaKishorM/laya)提供相近的决策思路。具体字段、权重、部署方式和许可证在实施时锁定版本并核验，不让服务协议进入核心 DTO。

V1 决策 schema 固定为：

| 字段 | 类型/候选值 | 用途 |
| --- | --- | --- |
| `replyNeed` | `reply`, `optional`, `no_reply`, `uncertain` | 决定是否展示“无需回复”提示 |
| `intent` | `question`, `request`, `social`, `information`, `conflict`, `other` | 控制候选内容侧重点 |
| `tone` | `neutral`, `warm`, `formal`, `brief` | 控制风格 |
| `risk` | `normal`, `sensitive`, `high`, `unknown` | 降级或要求人工判断 |
| `strategy` | `answer`, `clarify`, `acknowledge`, `defer`, `decline` | 限定生成方向 |
| `confidence` | 0～1；按字段保存 | 低置信度触发保守降级 |

这些标签是产品内部 schema，并非 JEV/Laya 的固定输出。Provider Adapter 负责将其映射为服务支持的问题形式，再映射回内部值。`risk=high/unknown` 或关键字段置信度低于可配置阈值时，不自动生成确定性答案；显示“建议自行判断”或只生成澄清类候选。阈值初值由测试集校准，不能把概率当作事实保证。决策失败可回退到确定性规则（如最后一条非文本则只提示无法理解内容），不以未验证的猜测伪装正常判断。

### 3.4 Generation Engine 与候选校验

生成 Provider 接收经过许可的 `ContextSnapshot`、`DecisionResult` 和可选的用户风格设置。系统约束包括：只基于可见文本，不编造事实，不声称已查看图片/听过语音，不承诺用户未授权的行动；输出 2～3 条简短、彼此有明显差异的候选。候选按 JSON 数组解析，若 Provider 返回自由文本，适配器必须严格解析与校验，不能直接注入 UI。

`CandidateValidator` 检查非空、长度上限、重复、控制字符、不可见字符、URL/电话号码等高风险内容，并确认每条仍符合当前会话；风险检查是提示与阻断的补充，最终决定权在用户。文本只显示与填草稿，不调用发送接口。

### 3.5 Overlay 与交互

入口放在当前聊天页、紧邻输入区且不遮挡原生发送按钮。状态包含“生成”“取消”“重新生成”和错误重试；候选卡片标注“AI 建议，发送前请检查”。点选候选后将其填入输入框，Overlay 收起或保留小状态提示。界面需支持键盘弹出、旋转/安全区、动态字体、VoiceOver、深色模式与微信页面转场。Overlay 必须随页面释放，不能持有聊天控制器导致内存泄漏。

## 4. 内部数据契约

以下为跨模块契约示意，字段名可直接作为 JSON/模型类型定义；所有结构包含 `schemaVersion=1`。可识别个人的信息仅存内存，远程传输前按隐私设置转换。

```json
{
  "ChatMessage": {
    "localId": "ephemeral-string",
    "sessionId": "ephemeral-session-key",
    "senderId": "ephemeral-speaker-key",
    "direction": "incoming|outgoing|system",
    "kind": "text|image|audio|video|file|location|other",
    "text": "string-or-null",
    "timestampMs": 0,
    "isRecalled": false,
    "isPartial": false
  },
  "ContextSnapshot": {
    "schemaVersion": 1,
    "requestId": "uuid",
    "sessionId": "ephemeral-session-key",
    "pageToken": "uuid",
    "snapshotHash": "hash",
    "messages": ["ChatMessage"],
    "partial": false,
    "createdAtMs": 0
  },
  "DecisionResult": {
    "schemaVersion": 1,
    "replyNeed": "reply|optional|no_reply|uncertain",
    "intent": "question|request|social|information|conflict|other",
    "tone": "neutral|warm|formal|brief",
    "risk": "normal|sensitive|high|unknown",
    "strategy": "answer|clarify|acknowledge|defer|decline",
    "confidence": {},
    "providerId": "string",
    "modelVersion": "string"
  },
  "Candidate": {
    "id": "uuid",
    "text": "string",
    "style": "brief|warm|formal",
    "snapshotHash": "hash"
  }
}
```

核心接口（伪代码）：

```text
WeChatAdapter.currentSession() -> SessionHandle?
WeChatAdapter.readRecentMessages(handle, limit) -> Result<RawMessage[]>
WeChatAdapter.fillDraft(text, expectedHandle, expectedHash, overwriteChoice)
    -> Result<FillOutcome>
MessageAdapter.normalize(rawMessages, handle) -> Result<ChatMessage[]>
ContextEngine.build(messages, budget) -> ContextSnapshot
PrivacyGate.authorize(snapshot, provider) -> Allow | NeedsConsent | Deny
DecisionProvider.decide(snapshot, cancellation) -> Result<DecisionResult>
GenerationProvider.generate(snapshot, decision, cancellation) -> Result<Candidate[]>
SessionCoordinator.cancel(requestId)
```

`Result` 的错误至少区分 `unsupportedVersion`、`staleSession`、`permissionDenied`、`network`、`timeout`、`providerInvalid`、`inputUnavailable`、`cancelled`。所有异步回调必须携带 `requestId`；UI 消费结果前二次校验 `pageToken + sessionId + snapshotHash`。

## 5. 状态机与时序

```text
Disabled/Unsupported
        │ 兼容性通过 + 用户启用
        ▼
Idle ──用户点击──▶ Capturing ──▶ PrivacyCheck ──▶ Deciding ──▶ Generating
 ▲                    │                │              │              │
 │                    └─失败────────────┴─失败─────────┴─失败─────────┘
 │                                 Error（可重试）                   │
 │                                                                  ▼
 └──页面离开/会话变化/取消/填入成功◀── Ready ◀── Validating ◀────────┘
                                         │
                                         └─用户点选─▶ Filling ──▶ Idle
```

每次新生成取消旧请求。`Capturing` 时确认页面与会话；`Ready` 中若收到新消息则标记候选过期并要求重新生成。`Filling` 前再次取当前会话和草稿状态。任一状态遇到页面离开、微信账号切换或插件关闭，立即取消请求、清除内存上下文并移除 Overlay。回调迟到只丢弃，不重新显示。

## 6. Hook 点发现与版本兼容

微信内部类名、Selector 和字段属于未公开实现，本文不虚构固定 Hook 名称。适配工作以具体微信安装包版本为单位，记录证据并维护 `CompatibilityManifest`：`wechatVersion`、`build`、`iosRange`、`architecture`、`jailbreakScheme`、适配器实现版本、页面/消息/输入框探针状态及设备验证结果。

发现流程：在自有测试设备上确认聊天页面类与生命周期 → 找到当前会话稳定标识 → 观察当前页面消息数据源和更新路径 → 确定输入框控件及其合法的文本变更入口 → 用最小只读探针验证 → 写入适配清单与回归样例。记录所依据的运行时观察，不将某版本私有符号扩散到业务模块。仅当三个探针均通过，才展示完整功能；消息探针失败则隐藏生成，草稿探针失败则禁用填入并显示可复制候选（如已获用户许可生成）。未知版本默认关闭。

每次微信更新后先在测试设备执行兼容性检查，再发布对应适配器。进程启动时做轻量 capability 检测；运行中出现连续异常或崩溃标记，下一次启动进入安全模式。不得通过模糊扫描任意私有对象来“猜测”兼容性。

## 7. Provider 抽象与部署

决策 Provider：`JevDecisionProvider`、`LayaDecisionProvider`、`RulesDecisionProvider`。生成 Provider：`RemoteTextGenerationProvider`，以后可扩展本地文本模型。JEV 使用其官方服务时需按官方文档固定 API 与模型版本；Laya 的本地部署形态应由设备可用算力和实际仓库支持范围决定，V1 可通过本机/受控端点适配，但不可宣称它已在 iPhone 微信进程内可稳定运行。生成文本仍需单独的生成模型。

Provider 配置包含 `id`、endpoint、模型标识、超时、输入预算、隐私模式、启用状态。远程端点必须 HTTPS，证书校验不得关闭。API 密钥由安全存储保存，不放在偏好文件、源码、日志或请求 URL 中；若越狱环境无法可靠满足密钥存储与进程隔离要求，应改为用户自己运行的受控服务，并在交付前验证其威胁模型。网络请求只传完成当前任务所需的消息文本和会话内匿名发送者标签，不传联系人 ID、头像或微信账号标识。

## 8. 配置、日志与隐私

| 设置 | V1 默认值 | 说明 |
| --- | --- | --- |
| 插件启用 | 关闭 | 用户主动开启 |
| 远程传输 | 关闭 | 单独说明接收方与内容范围 |
| 上下文消息数 | 20 | 可调整并受硬上限约束 |
| 候选数量 | 3 | 实际有效结果允许 2～3 条 |
| 敏感会话模式 | 开启 | 可排除指定会话；排除标识仅本地保存 |
| 自动生成 | 关闭且 V1 不提供 | 用户点击才执行 |
| 聊天内容日志 | 永久关闭 | 不提供开启选项 |

日志仅记录事件名、错误码、模块、耗时、已脱敏版本信息和随机请求 ID。不得记录原始消息、候选正文、联系人名称、会话 ID、完整请求/响应和 API 密钥。默认内存环形缓冲，诊断导出须用户主动操作且先展示内容。进程退出、会话切换后清理快照和候选；取消远程传输许可后立即停止新请求并删除关联缓存。排查问题使用人工构造的测试会话与脱敏样例。

## 9. 失败降级与质量门槛

| 故障 | 行为 |
| --- | --- |
| 微信版本未知或 Hook 校验失败 | 不展示入口或禁用相关能力，保留微信原生功能 |
| 会话/消息无法可靠识别 | 不生成；提示“当前会话暂不支持” |
| 媒体消息无文本 | 用类型占位；缺少关键内容时只给澄清建议或不生成 |
| 无许可/网络断开/超时 | 明确提示原因和重试入口；不得绕过许可切换 Provider |
| 决策结果无效或低置信度 | 规则降级或展示“不确定”；不输出确定性事实 |
| 生成结果为空、重复或越界 | 丢弃无效候选；不足 2 条时提示失败并可重试 |
| 用户切换会话/收到新消息 | 取消或废弃旧结果；填草稿前再次验证 |
| 输入框已有草稿 | 用户选择覆盖或取消；默认不覆盖 |
| 写入失败 | 不尝试发送；恢复/保持原草稿并提示失败 |

测试至少覆盖：DTO 映射与边界值、上下文截断、隐私门控、Provider 协议解析、取消与迟到回调、会话串线、草稿覆盖、微信升级后的兼容探针。用模拟适配器完成大部分自动化测试；真机手测覆盖进入/退出聊天、键盘切换、连续新消息、群聊、撤回、空草稿和非空草稿、离线和弱网。发布门槛是目标版本矩阵中无误发、无串会话、无明显卡顿或启动崩溃；目标性能阈值在首轮设备基线后量化并写入测试报告。

## 10. 建议目录结构

```text
project/
├── Makefile
├── package/                     # 打包元数据与安装过滤配置
├── tweak/
│   ├── Bootstrap.xm
│   ├── WeChatAdapter/            # 私有类/Selector/版本清单，仅此处依赖微信实现
│   │   ├── ChatPageProbe.*
│   │   ├── MessageProbe.*
│   │   ├── DraftWriter.*
│   │   └── CompatibilityManifest.json
│   ├── MessageAdapter/
│   ├── ContextEngine/
│   ├── PrivacyGate/
│   ├── DecisionEngine/
│   ├── GenerationEngine/
│   ├── Providers/
│   ├── Overlay/
│   ├── SessionCoordinator/
│   └── ConfigTelemetry/
├── contracts/                   # DTO schema、错误码、Provider 协议
├── tests/                       # 模拟微信对象、契约测试、脱敏样例
├── docs/                        # 兼容矩阵、Hook 发现记录、隐私说明、测试报告
└── scripts/                     # 本地构建与验证脚本
```

若工程语言和构建系统要求不同，可调整文件扩展名与目录细节，但必须保持“微信私有实现只在适配层”和“无发送接口”的依赖边界。

## 11. V1 开发顺序与交付物

1. **确定测试矩阵与隐私说明**：锁定设备、iOS、越狱方式、微信版本和 Provider；建立兼容清单、同意文案和脱敏样例。
2. **搭建可安装的最小 Tweak**：仅在目标微信进程注入，提供启用/关闭和安全模式，验证不影响原生聊天。
3. **实现只读适配器**：页面、会话、消息探针；产出当前会话 DTO 与版本发现记录。
4. **实现草稿写入与 Overlay**：先用固定测试候选验证“点选只填入”；覆盖非空草稿、会话变化和 UI 生命周期。
5. **实现 ContextEngine、PrivacyGate 与状态机**：模拟 Provider 跑通取消、超时、过期结果和许可门控。
6. **接入 Decision Provider 与生成 Provider**：先以固定 schema/模拟响应完成契约测试，再接真实服务并固定版本；校准阈值。
7. **真机回归与发布包**：完成版本矩阵、故障注入、隐私审查、性能测量及可回滚安装包。

每阶段应交付可运行的最小增量、对应测试记录和已知限制。若没有可用的越狱测试设备或可验证的微信版本，先完成模拟适配器与契约测试，不能把“已编译”写成“已真机验证”。

## 12. 开发 Agent 约束

1. 以本文件为 V1 范围基线；遇到微信私有符号、目标版本、Provider 凭据或设备信息缺失时，先建立可替换接口与模拟实现，列出需真机确认的事实，不编造 Hook 点。
2. 每个模块只依赖上述公开内部契约；禁止在 `WeChatAdapter` 以外引用微信私有类。不得新增发送、自动点击、后台轮询、批量处理路径。
3. 每次提交说明目标版本、改动模块、风险、验证方式与结果。修改适配层时更新兼容清单和回归记录。
4. 不把真实聊天、账号数据、密钥放进源码、测试快照、日志或工单。网络调用必须经过 `PrivacyGate`。
5. 优先保证微信原生稳定性：Hook 中调用原实现、避免主线程耗时、所有异常安全退回、未知版本默认关闭。
6. “完成”需有可安装构建、真机操作证据和第 1.1 节验收项记录；缺少真机证据时明确标记为待验证。

## 13. 待确认的实施参数

架构可先按上述边界实施；以下参数在接触真机或 Provider 前填入项目配置，而不是由 Agent 猜测：目标 iOS/微信/越狱版本矩阵；是否优先支持群聊；JEV、Laya 与文本生成服务的实际接入渠道；本地或远程处理偏好；候选语言和用户风格；敏感会话排除策略。任何参数变化都不得突破“仅建议并填草稿、用户手动发送”的 V1 边界。

## 参考资料

- [Theos 官方文档：Logos 语法](https://theos.dev/docs/logos-syntax)
- [Theos 官方文档：rootless 构建](https://theos.dev/docs/rootless)
- [TypeSafe AI 官方文档：JEV Quick start](https://docs.typesafe.ai/introduction/quickstart)
- [Laya 项目源码](https://github.com/NandhaKishorM/laya)
- [Apple Developer：Keychain Services](https://developer.apple.com/documentation/security/keychains)

这些资料用于确认工具和模型的公开能力；微信私有实现、具体设备兼容性及 Provider 服务条款仍需按实施时的目标版本验证。
