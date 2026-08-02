# TomoRead 以 ColorTxt 为功能目标的差距分析与路线图

> 对照基线：`reference/ColorTxt-main`，调研快照为其 `package.json` 标注的 3.3.0。
> 目标：在保持 TomoRead“本地 EPUB/PDF + 知识整理 + AI 阅读”定位的前提下，逐步达到 ColorTxt 在本地阅读、阅读效率、数据可携带性和 AI 辅助方面的成熟度。
> 非目标：复制 ColorTxt 的 Electron/Vue/Monaco 架构或其未获得许可的实现代码。

## 1. 结论先行

ColorTxt 是一个功能广、以 TXT/Markdown 小说阅读为中心的桌面应用；TomoRead 则已在原生 EPUB/PDF 阅读、结构化标注/笔记、阅读统计和 Flutter 跨平台基础上具备优势。若以 ColorTxt 为目标，最有效的路线不是先堆更多格式，而是按以下顺序补齐能力：

1. **先加固可靠性和数据安全**：阅读定位回归、备份恢复、缓存诊断、Android 性能；
2. **补齐本地阅读效率工具**：TXT/Markdown、全文搜索、导入字体、脚注/图片、文本前景色、转换与快捷键；
3. **补齐可携带性与语音**：书库备份包、WebDAV、系统 TTS；
4. **让 AI 建立在本地检索上**：正文分块、RAG、上下文、可视化产物；
5. **最后评估在线书源、编辑器、多格式和角色化能力**：这些涉及合规、维护成本或会改变产品定位。

“ColorTxt 功能对齐”指用户能力和质量门槛对齐，不要求采用其“电子书转 Markdown + Monaco 编辑器”的技术路线。TomoRead 应继续使用 Flutter、Riverpod、SQLite、Foliate.js 与 `pdfrx`。

## 2. 对照范围和判断标准

### 2.1 资料依据

ColorTxt 的能力主要依据其仓内以下文档和对应入口源码：

- `docs/基础功能.md`：书库、格式转换、全屏、定时滚动、书包、展示转换、搜索、配色、标注、快捷键、数据管理；
- `docs/AI功能.md`：模型配置、向量检索、Agent、思维导图、词云、智能排版和 Token 用量；
- `docs/语音朗读.md`：系统/云端 TTS、多音色和播放控制；
- `docs/书源找书.md`：Legado 书源、搜索、书架和在线阅读；
- `docs/开发构建.md`：桌面构建、文件关联和发布能力。

TomoRead 的判断以 `lib/` 源码、测试、`README.md` 及 `.agent/` 设计文档为准；README 与源码不一致时，以源码为准。

### 2.2 状态含义

| 状态 | 含义 |
| --- | --- |
| 已对齐 | 已有真实数据、可操作 UI、持久化闭环和必要测试 |
| 部分 | 主流程已存在，但平台、交互深度、可靠性或数据闭环不足 |
| 缺失 | 当前没有可用实现 |
| TomoRead 优势 | 已满足目标且在阅读模型、跨平台或数据模型上更适合 TomoRead |
| 需决策 | 可参考，但实现前必须确认产品边界、授权、合规或隐私方案 |

## 3. 功能矩阵

### 3.1 书库、导入和格式

| ColorTxt 能力 | TomoRead 现状 | 状态 | 对齐目标与处理方式 |
| --- | --- | --- | --- |
| TXT、Markdown、EPUB、MOBI/AZW3、FB2/FBZ、PDF、CHM 打开 | 原生 EPUB/PDF 导入、托管、元数据和去重 | 部分 | P1 后按需求优先加入 TXT、Markdown；再评估 FB2、MOBI/AZW、CBZ。每种格式都须有封面、目录、进度、搜索、定位、错误恢复，不仅能打开。 |
| 电子书转换为 Markdown、内链/图片保留 | EPUB 使用 Foliate.js，PDF 使用 `pdfrx`，不改写原书 | TomoRead 优势/差异 | 保持原生 EPUB/PDF 渲染；只为 TXT/Markdown 建立独立解析管线。不要为了格式统一将 EPUB/PDF 降级为 Markdown。 |
| 文件夹扫描、拖放、分类、排序、批量维护、失效文件清理 | 书库搜索、格式筛选、分类、标签、收藏和批量管理已存在 | 部分 | 增加桌面拖放、文件夹导入、失效书籍诊断，以及 Android 文件关联/分享入口。 |
| 默认文件关联、双击打开 | Windows/Linux 构建可用，尚无阅读格式关联闭环 | 缺失 | 为 EPUB/PDF/TXT/Markdown 定义各平台打开策略；Android 处理 `ACTION_VIEW` 与分享流。 |
| 彩读书包 `.ctz/.ctzx`：导入、导出、加密 | Markdown/JSON 标注导出；无整库/书籍包 | 缺失 | 不兼容或复用 ColorTxt 书包格式。设计 TomoRead 自有、版本化且有 manifest 的备份包，随后支持可选加密。 |

### 3.2 阅读器、视觉与效率

| ColorTxt 能力 | TomoRead 现状 | 状态 | 对齐目标与处理方式 |
| --- | --- | --- | --- |
| 全屏阅读、自动隐藏/感应式工具栏、可调侧栏 | 沉浸式阅读、桌面可调侧栏、移动抽屉/底部面板 | 部分 | 继续提升全屏边缘呼出、快捷键和焦点处理；不能让浮层挤压正文或打断阅读位置。 |
| 字号、行高、正文宽度、字体、主题配色 | 全局/单书字体、字号、行距、边距、单双栏、主题 | 已对齐 | 增加导入字体及按书字体选择；保留现有全局/单书覆盖模型。 |
| 文本前景色：按引号、括号、标点、数字、英文及自定义词条变色 | EPUB 已有五类语义 token、亮/暗色板、总开关和单书覆盖；使用独立 CSS Highlight 前景色 | 部分 | EPUB 首版已完成，并与标注、搜索和 CFI 隔离；后续补跨内联节点匹配、词条管理增强与 PDF 支持。 |
| 简繁、全半角、文本替换等展示转换 | 无 | 缺失 | 先实现可逆的展示层简繁/全半角转换，原书不改写；文本替换需有范围、预览、禁用和性能约束。 |
| 章节规则、黏性章节标题、快速查找 | EPUB/PDF 目录、章节跳转、EPUB 文本搜索、PDF 搜索 | 部分 | 完善章节内/全书搜索和结果导航；TXT/Markdown 接入后再提供章节识别规则与黏性标题。 |
| 脚注浮层、图片查看、内外链策略 | 基础 EPUB 渲染，相关交互不完整 | 缺失 | P1 增加脚注浮层、图片灯箱、外链确认策略；不得破坏 CFI、分页和返回位置。 |
| 定时滚动、番茄时钟 | 无 | 缺失 | 在阅读活动追踪稳定后增加；与 TTS、后台、锁屏和 Android 生命周期协调。 |
| 快捷键配置与冲突校验 | 有常规阅读器交互，无可配置快捷键中心 | 缺失 | 先定义跨平台命令表，再开放桌面自定义与冲突检测；移动端不强行复用桌面按键。 |
| 正文编辑模式 | 笔记可编辑，书籍原文只读 | 需决策 | EPUB/PDF 编辑不应进入近期范围；TXT/Markdown 可在未来以“副本编辑/导出”为独立功能立项。 |

### 3.3 标注、笔记、知识管理与统计

| ColorTxt 能力 | TomoRead 现状 | 状态 | 对齐目标与处理方式 |
| --- | --- | --- | --- |
| 书签、划线/背景标注、笔记、侧栏列表和导出 | EPUB 书签/高亮/笔记、全局笔记、Markdown/JSON 导出、原文回跳 | TomoRead 优势 | 重点是加固 locator 回跳与补齐 PDF 标注，不必重做数据模型。 |
| 自定义高亮词全局收藏和单书覆盖 | 已支持从 EPUB 选区保存全局/单书词条、最长优先、单书覆盖、重复词更新及删除 | 部分 | 已使用独立 `TextColorTerm`，未污染 `ReadingAnnotation`；后续补搜索、直接改色、批量操作、导入导出与 Unicode NFC 归一化。 |
| 全书侧栏搜索 | 当前为书库/笔记/阅读器的分散搜索 | 部分 | 建立 `BookContentExtractor` 和统一搜索入口，覆盖书名、元数据、标注与正文并保留 locator。 |
| 阅读时长和基本进度 | 日/周/月/年/全部统计、时长、活跃天数、连续阅读和排行 | TomoRead 优势 | 在稳定采集基础上再增加目标、热力图、ETA、导出和年度报告。 |
| 角色卡与人物资料 | 无 | 需决策 | 仅在小说阅读成为明确场景后引入；先以 AI 从书内检索生成“人物卡草稿”，必须由用户确认并可追溯引用。 |

### 3.4 语音、翻译和辅助阅读

| ColorTxt 能力 | TomoRead 现状 | 状态 | 对齐目标与处理方式 |
| --- | --- | --- | --- |
| 系统语音、Edge TTS、云 TTS，多引擎连接测试 | 无 TTS | 缺失 | 先做系统 TTS + 播放/暂停/停止/速率/音量/当前位置游标；Provider 接口独立于 AI Gateway。 |
| 朗读队列、预取、上一句/下一句、缓存 | 无 | 缺失 | EPUB 先按章节文本段落切块；PDF 待文本层可靠后接入。播放状态必须和阅读统计、后台/锁屏状态一致。 |
| 旁白/对白多音色、AI 说话人识别和情绪 | 无 | 缺失 | 作为远期增强，不应阻塞基础 TTS；需要明确 Token 成本、隐私和错误回退。 |
| 选区/章节翻译 | 无 | 缺失 | P3 增加选区翻译和可选缓存，使用现有 AI Provider 或独立翻译 Provider；输出不可伪装成原文。 |

### 3.5 AI、检索与可视化

| ColorTxt 能力 | TomoRead 现状 | 状态 | 对齐目标与处理方式 |
| --- | --- | --- | --- |
| 多 Provider 配置、密钥保险库、连接测试、Token/成本显示 | OpenAI 兼容端点、系统安全存储、流式对话、用量记录 | 部分 | 加入连接测试、Token/成本展示和专用 OpenAI Responses、Anthropic、Gemini adapter。 |
| 本地/远程 embedding、向量索引与章节 RAG | 无持久化正文分块或向量检索 | 缺失 | 先做 `content_chunks` 和关键词搜索，再加入可插拔 embedding 与混合检索。没有 AI 配置时本地搜索必须独立可用。 |
| Agent 工具、章节上下文、深度思考 | 已有结构化 Part、只读工具、技能、工具循环和引用 | 部分 | 已完成第一轮 Agent 基础设施；下一步是 `ReadingContextAssembler`、长会话摘要、精确 token 预算和 PDF 文本工具。 |
| 思维导图、词云、AI 图像/角色视觉资产 | 无 | 部分/需决策 | 先增加可导出的 Markdown 大纲/思维导图与词云；文生图和角色立绘不进入近期核心路线。 |
| AI 智能排版/清理原文 | 无 | 需决策 | 仅为用户副本或导出文本提供 Diff 预览和显式确认；绝不直接覆盖托管 EPUB/PDF。 |

### 3.6 同步、备份、在线书源与平台

| ColorTxt 能力 | TomoRead 现状 | 状态 | 对齐目标与处理方式 |
| --- | --- | --- | --- |
| WebDAV：设置、书包、书架、书源同步 | 无同步 | 缺失 | 先完成实体级版本、软删除/墓碑、冲突测试和备份；再做手动 WebDAV，同步数据库实体、封面和书籍文件。 |
| 缓存清理、数据重置、失效文件诊断 | 无系统化工具 | 缺失 | P0 增加存储诊断、按类别清理缓存、导出前检查、失败回滚。 |
| 在线书源、发现、搜索、书架、登录/验证码、代理 | 仅本地书库 | 需决策 | 这是一个独立产品域。立项前需完成内容来源授权、地区合规、反爬风险、账号凭据隔离和用户隐私评估；不把未经授权的来源当作默认能力。 |
| Windows/Linux/macOS 桌面发行与自动更新 | Windows/Linux release；Android 实验性；无 macOS/iOS | 部分 | 加固现有 Windows/Linux；随后补 macOS；移动端以 Android 成熟度优先。自动更新需独立的签名、回滚和发布策略。 |
| TXT/Markdown 文件关联及桌面“找书”独立窗口 | 无 | 缺失 | 文件关联属于格式扩展阶段；“找书”窗口仅在在线书源域获批准后实现。 |

## 4. TomoRead 必须保留的优势与架构决策

1. **原生 EPUB/PDF 阅读**：不为了 ColorTxt 的文本工作流而把 EPUB/PDF 统一转成 Markdown；这会降低版式、资源、定位和标注的可靠性。
2. **SQLite + Repository + Riverpod**：同步、备份、标注、对话和统计均依赖事务与关系查询；不迁移到 Electron 的 localStorage 模式。
3. **结构化标注与知识页**：`ReadingAnnotation`、全局笔记、导出和 AI 引用继续使用同一 ID/locator 链路。
4. **安全存储**：所有 AI、TTS、WebDAV 等密钥继续放在系统安全存储；SQLite、导出和同步配置不能含明文密钥。
5. **桌面与移动共享业务逻辑**：Flutter UI 可按平台调整，但数据模型、Repository、统计与同步协议必须一致。
6. **本地优先**：阅读、搜索、笔记和基础统计在无网络、无 AI Key 的情况下仍完整可用。

## 5. 分阶段路线图

### Phase 0：发布后可信度基线（P0）

- EPUB 定位、分页、滚动、目录、书签和标注跳转的回归样本；
- Android 导入/解压/解析移出 UI isolate，并记录启动和打开阅读器性能基线；
- 版本化整库备份、校验、原子恢复、缓存清理和存储诊断；
- 定义可测试的 locator contract。

**完成标准**：升级、恢复、主题/布局切换不会丢失阅读位置、标注、笔记、对话和统计数据。

### Phase 1：ColorTxt 本地阅读效率对齐（P1）

- 桌面拖放、文件夹导入、Android 文件关联/分享入口；
- EPUB 脚注浮层、图片查看、内外链策略、导入字体；
- TXT/Markdown 导入与解析；
- `content_chunks`、关键词全文搜索和统一搜索结果跳转；
- 阅读器文本前景色（文本 token 与自定义词条，EPUB 首版已完成）；
- 展示层简繁/全半角转换、基础快捷键命令表。

**完成标准**：无需 AI 配置，也能管理本地书库、搜索正文、跳回原文，并按用户偏好完成舒适阅读。

### Phase 2：语音、备份包和同步（P2）

- 系统 TTS 与播放控制，之后接入可选云端 TTS Provider；
- TomoRead 版本化书籍/整库备份包、可选加密、导入检查；
- 同步所需的更新时间、软删除/墓碑和合并测试；
- 手动 WebDAV 同步与可观察的进度/错误恢复。

**完成标准**：用户可离线阅读并安全备份；两个设备离线修改后不会静默丢失数据或复活已删除内容。

### Phase 3：ColorTxt AI 深度对齐（P2-A）

- 本地/远程 embedding，关键词 + 向量混合检索；
- `ReadingContextAssembler` 和全书证据引用；
- 长会话摘要、Provider adapter、连接测试、Token/成本展示；
- 可导出的思维导图/大纲和词云；
- PDF 文本检索与 AI 工具。

**完成标准**：针对未打开章节提问时，AI 能给出可回跳、可核验的书内证据；模型不可用不影响阅读与本地搜索。

### Phase 4：选择性扩展（P3）

- FB2、MOBI/AZW、CBZ 等格式按用户需求逐个接入；
- 翻译、番茄时钟、定时滚动、阅读目标、热力图和统计导出；
- macOS/iOS 正式支持；
- 多音色 TTS、人物卡、AI 智能排版、可视化资产；
- 在线书源/找书仅在完成独立的合规产品评审后立项。

## 6. 首批可独立验收的 Issue

1. `Reader locator contract and EPUB regression fixtures`
2. `Versioned full-library backup and atomic restore`
3. `Storage diagnostics and cache cleanup`
4. `Android import and reader performance baseline`
5. `Desktop drag-and-drop, folder import, and Android share intents`
6. `EPUB footnote overlay, image viewer, and external-link policy`
7. `TXT and Markdown import with chapter and locator contracts`
8. `Content chunk schema and lexical full-text search`
9. `Reader text-coloring profile and EPUB runtime ranges`
10. `System TTS reader session with locator cursor`
11. `Sync-ready tombstones, revisions, and merge tests`
12. `WebDAV manual sync with recoverable progress`

前四项是所有 ColorTxt 对齐工作的前置条件。第 7 至 9 项形成“文本阅读效率”闭环；第 10 至 12 项形成“可携带、可持续阅读”闭环。

## 7. 不可违反的约束

1. ColorTxt 参考目录中未发现项目许可证文件；只可参考产品行为与公开格式，不得复制其源码、资源、文案或私有协议。
2. 任何新格式必须先定义导入、封面、目录、定位、搜索、错误恢复和删除语义；不能只实现渲染。
3. 不把同步实现为上传整个 SQLite 文件；使用实体级记录、版本、删除语义和冲突策略。
4. 任何 AI 写入、智能排版、人物资料或翻译缓存都必须经用户确认，并可回溯到原文或独立副本。
5. 密钥、登录 cookie、验证码和 WebDAV 密码不得进入 SQLite、备份包、日志或普通导出。
6. 在线书源不是“本地阅读器功能”的自然延伸，必须先获得明确的产品与合规授权。

## 8. 维护规则

### 8.1 交付与验收约定

本路线图下的功能任务采用轻量交付标准：**不要求本地编译、构建或运行测试**。开发者完成已约定范围内的代码与文档改动后，创建语义明确的 Git commit 并成功推送至约定远端分支，即视为该任务完成验收。

任务说明仍应写清功能范围、数据迁移和用户可见行为，便于后续维护者审阅提交历史；但不得将本地编译、构建产物或测试运行结果设为交付前置条件。CI 是否在远端运行由仓库工作流自行决定，不属于开发者的本地验收步骤。

### 8.2 文档同步

每完成一个 Phase 或新增一个大功能时，需要同时更新：

1. 本文矩阵中的 TomoRead 状态与差距；
2. `.agent/feature-gap-analysis.md` 的优先级；
3. 对应架构文档（文本前景色、AI、笔记、统计等）；
4. README 的能力清单、平台说明与 Release Notes；
5. 测试清单和数据库 migration 记录。
