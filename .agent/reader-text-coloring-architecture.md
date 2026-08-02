# TomoRead 阅读器文本前景色（字体变色）设计

> 状态：EPUB 首版已实现（Phase A–C 基础范围）
> 实现基线：2026-08-02
> 首个支持范围：EPUB；PDF 在其文本选区与全文定位稳定后接入。

## 0. 当前实现状态

EPUB 首版已完成以下闭环：

- 全局总开关、五类语义 token 开关，以及亮色/暗色主题的独立前景色色板；
- 单书“跟随全局 / 开启 / 关闭”覆盖设置；
- 从正文选区创建全局或单书词条，并在管理弹窗中查看、删除词条；
- SQLite v12 持久化、同范围重复词条更新、全局 500 条/单书 300 条和单条 100 字符限制；
- Foliate.js 章节 iframe 内使用 `Range` + CSS Custom Highlight API 渲染，词条优先于语义 token，单书词条在同长度冲突时优先于全局词条；
- 与背景标注、搜索高亮、CFI/locator 和原始 EPUB DOM 隔离；运行环境不支持 Custom Highlight 时静默降级。
- `TextColoringSettingsNotifier` 的持久化命令命名为 `saveSettings`，不得命名为 `update`，以避免覆盖 Riverpod `AsyncNotifier.update` 的框架方法。

当前限制：仅支持 EPUB；词条、引号和括号只在单个 `Text` 节点内匹配，不跨内联标签或段落；词条管理首版只提供查看和删除，改色可通过重新选择同一词条并保存完成；尚无搜索、批量操作、导入导出与 PDF 渲染；规范化目前包含首尾裁剪、连续空白折叠和大小写归一，Unicode NFC 归一化留待后续补齐；上限词条集的异步取消与性能基线尚未完成。

## 1. 目标与边界

为阅读器增加**文本前景色**能力：让读者可按文本类型或自定义词条改变文字颜色，以辅助扫读、区分中英文、识别数字和关注人物/术语。

它不是现有的“高亮标注”功能：

| 能力 | 目的 | 是否写入笔记/标注 | 是否改变阅读位置 |
| --- | --- | --- | --- |
| 文本前景色 | 阅读偏好与视觉辅助 | 否 | 否 |
| 背景高亮、划线、笔记 | 保存读者的阅读记录 | 是 | 可跳回原文 |

文本前景色必须是可随时关闭、不会修改 EPUB 源文件、不会改变 CFI/locator、不会进入 AI 上下文或笔记导出的展示层偏好。无障碍上不得只依赖颜色传递书籍事实；关闭后正文仍以主题的正文色正常阅读。

## 2. 对 ColorTxt 的调研结论

调研对象：`reference/ColorTxt-main`。

ColorTxt 将“字体变色”拆成两条互不混淆的能力：

1. **文本类型着色**：为引号内容、括号内容、标点、特殊标记、数字和英文分别提供前景色；亮/暗主题各有独立调色板，且每个类型可单独关闭并回退至正文色。
2. **自定义词条着色**：选区可添加为词条；词条按颜色槽位保存，支持全局收藏和单书词表。渲染时单书词条覆盖全局词条，较长词优先，避免短词吞掉长词。

其关键工程约束也适用于 TomoRead：词条需要长度和数量上限、按字面量匹配而非让用户输入任意正则、展示层文本与持久化原文要区分、主题色与是否启用要分别保存。

ColorTxt 当前参考目录未发现可授予代码复用权的许可证文件。因此本方案只借鉴可观察到的产品行为和通用设计原则，**不得复制其源码、正则规则或 UI 文案**。

## 3. 产品范围

### 3.1 第一版：EPUB 文本类型着色

提供总开关和以下可选类型。每种类型关闭后直接使用正文色，已配置的颜色仍保留。

| token | 初始规则 | 说明 |
| --- | --- | --- |
| `latin` | 连续拉丁字母及常见词内连字符/撇号 | 便于中文书中识别英文术语；默认关闭，避免英文书整页变色 |
| `number` | Unicode 数字序列 | 便于识别年份、编号与数值；默认关闭 |
| `punctuation` | Unicode 标点符号 | 默认关闭；低对比度颜色，不能影响正文阅读 |
| `quoted` | 同一文本节点内的成对中英文引号内容 | 默认关闭；跨节点、未闭合和嵌套引号在第一版不着色 |
| `bracketed` | 同一文本节点内的成对常用括号内容 | 默认关闭；规则与 `quoted` 相同 |

第一版不尝试模拟编程语言语法高亮，也不通过“颜色”标记章节、书名或任何不可靠的语义判断。

### 3.2 第二版：自定义词条

在 EPUB 选区菜单加入“文字颜色”入口：选中单段、非空文本后选择颜色并保存到“本书”或“全局”。

- 本书词条：只在当前书生效。
- 全局词条：所有 EPUB 书籍生效，适用于人名、专业术语和语言学习词汇。
- 同一规范化词条同时存在时，本书规则覆盖全局规则。
- 多个词条重叠时，最长精确匹配优先；长度相同时本书优先，再按创建时间稳定排序。
- 词条仅按字面量精确匹配。第一版不开放用户正则、模糊匹配和自动词性识别，避免 ReDoS、误匹配和不可预测的性能。

### 3.3 不进入第一版

- PDF 文字变色、扫描 PDF OCR 变色；
- AI 自动识别人物、情绪或“重要句”并永久变色；
- 修改/重写 EPUB 或将样式写回书籍文件；
- 用字体颜色替代现有背景高亮、笔记和导出；
- 对跨段落、跨 iframe 或跨章节的自定义短语匹配。

## 4. 交互与配色

### 4.1 设置页

在“阅读设置”增加“文本前景色”分组：

1. 总开关“启用文本前景色”；
2. 文本类型开关及颜色选择器；
3. 亮色/暗色主题分别编辑一套颜色；
4. “恢复默认文本颜色”只重置本功能，不影响应用主题、标注色或书籍阅读设置；
5. “管理词条”打开全局词条列表，可搜索、改色和删除。

每个 token 需显示小样文本和对比度提示。默认颜色必须满足与阅读背景的可读性要求；如果用户选择低对比度颜色，允许保存但显示警告，不自动替换用户颜色。

### 4.2 阅读器内

- 书籍设置弹窗可覆盖全局总开关，默认“跟随全局”。
- 选区菜单中的词条颜色使用前景色色板，而不是现有四个背景高亮色。
- 词条管理页需明确“全局 / 本书”范围和最终生效色；删除本书规则后若同名全局规则存在，应立即显示为全局色。
- 主题切换、分页/滚动切换、章节跳转和字号变化后都必须重新应用当前颜色，但不改变当前位置。

## 5. 数据模型与持久化

### 5.1 全局配置

在 `app_settings` 保存单一 JSON 键 `reader_text_coloring`。该键保存：

```json
{
  "enabled": false,
  "tokens": {
    "latin": { "enabled": false, "light": "#2E6B8A", "dark": "#8BC4E3" },
    "number": { "enabled": false, "light": "#8A5A20", "dark": "#F0BE75" },
    "punctuation": { "enabled": false, "light": "#6D7780", "dark": "#AAB4BE" },
    "quoted": { "enabled": false, "light": "#7B4E91", "dark": "#D9B8F0" },
    "bracketed": { "enabled": false, "light": "#476D4C", "dark": "#A5D6A7" }
  }
}
```

颜色以语义 token 名保存，不能以调色板数组下标作为持久化标识，避免用户重新排序后词条颜色漂移。

### 5.2 书籍覆盖与词条表

新增一次 SQLite migration：

```sql
CREATE TABLE book_text_coloring_overrides (
  book_id TEXT PRIMARY KEY,
  enabled INTEGER,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
);

CREATE TABLE text_color_terms (
  id TEXT PRIMARY KEY,
  book_id TEXT,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  color_token TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX text_color_terms_global_normalized
  ON text_color_terms(normalized_term) WHERE book_id IS NULL;
CREATE UNIQUE INDEX text_color_terms_book_normalized
  ON text_color_terms(book_id, normalized_term) WHERE book_id IS NOT NULL;
```

`book_id IS NULL` 表示全局词条；非空表示单书词条。`enabled` 允许 `NULL`，含义为跟随全局配置。目标规范化规则为 Unicode NFC、首尾空白裁剪、连续内部空白折叠和大小写归一；原始 `term` 用于界面展示。EPUB 首版已完成除 Unicode NFC 之外的规则，NFC 归一化作为后续兼容增强。

首版限制：每个词条最长 100 个 Unicode 字符、每本最多 300 条、全局最多 500 条。超出限制时拒绝保存并说明原因。Repository 必须在事务中执行“同范围同规范词条的改色/替换”，避免重复条目。

## 6. EPUB 渲染方案

TomoRead 的 EPUB 正文位于 Foliate.js 的章节 iframe 中，当前由 `assets/epub_reader_runtime/tomoread-reader.js` 与 `EpubWebView` 注入样式；现有 `CSS.highlights` 已用于标注和搜索。

推荐增加独立的 runtime 命令 `setTextColoring(config, terms)`，而不是让 Flutter 直接拼接 HTML。它的职责为：

1. 在当前章节 iframe 内用 `TreeWalker` 遍历可见正文的 `Text` 节点，跳过 `script`、`style`、`code`、`pre`、隐藏节点和已有 TomoRead 控制节点；
2. 对**原 Text 节点上的 Range**计算 token 与词条命中；不得拆分或用 `span` 包裹原始文本节点；
3. 将范围按最终 `color_token` 分组，创建命名空间为 `tomoread-text-color-*` 的 `Highlight`，并使用 `::highlight()` 只设置 `color`；
4. 新章节、样式重载、配置变更、主题切换前先清除这一命名空间，绝不清除 `tomoread-yellow`、`tomoread-search` 等标注/搜索高亮；
5. 不支持 `CSS.highlights` 或 `Highlight` 的 WebView 中静默降级为普通正文，不改变数据也不影响阅读。

使用 Range + CSS Custom Highlight 的原因是它不改写章节 DOM 结构，从而避免破坏 EPUB CFI、文本选区、搜索定位和现有标注定位。正文前景色、背景高亮和搜索高亮必须使用不同的 highlight 名称。

### 6.1 匹配与优先级

渲染器应对每个 Text 节点建立不重叠的最终区间，优先级如下：

1. 单书自定义词条；
2. 全局自定义词条；
3. 文本类型 token；
4. 阅读器正文色。

同层的词条按“更长优先，再按稳定顺序”处理。匹配必须在章节切换时可取消；任何异常、超时或无效范围都只跳过当前节点，不能阻塞翻页、滚动或读取位置。

为避免正则性能问题，先将词条按长度排序、转义为字面量，并按上限分批处理；不接受外部提供的正则表达式。拉丁字母大小写不敏感匹配，CJK 和其他文字按原字符匹配。第一版仅匹配单个 Text 节点，跨内联标签的词条留待后续版本。

### 6.2 与现有能力的关系

- `ReadingAnnotation` 继续只表示用户显式创建的背景高亮和笔记；文本前景色不新增 annotation。
- 搜索命中仍使用 `tomoread-search`；搜索背景必须盖过文字颜色，但搜索结束后文字颜色应恢复。
- 选区保存词条前必须读取原始选区文本，不能读取已经着色后的 DOM 文本。
- CFI、章节索引、滚动百分比和 `EpubLocation` 不因本功能而新增字段。

## 7. Flutter 分层与 API

新增以下职责，保持 Widget 不直接读写 SQLite：

```text
domain/models/text_coloring.dart
data/repositories/text_coloring_repository.dart
features/reader/text_coloring_controller.dart
features/reader/text_coloring_widgets.dart
assets/epub_reader_runtime/tomoread-reader.js
```

- `TextColoringSettings`：全局总开关、token 启用状态和亮/暗颜色；负责 JSON 向后兼容。
- `TextColorTerm`：全局或单书范围的原始文本、规范化文本、颜色 token 与审计时间。
- `ResolvedTextColoring`：合并全局配置、单书开关和有效词条，并生成只含已验证 token 的 runtime payload。
- `TextColoringRepository`：加载/保存配置、词条 CRUD，并按“本书优先、最近更新”顺序读取有效词表。
- `TextColoringController`：设置页与阅读器共用的 Riverpod 状态，修改成功后刷新依赖当前配置或书籍的渲染状态。
- `text_coloring_widgets.dart`：设置面板、选区保存弹窗和全局/单书词条管理 UI；不直接访问 SQLite。
- `tomoread-reader.js`：只消费 runtime payload，用独立 Highlight 命名空间完成匹配和渲染。

`ReadingSettings` 保留字体、字号、行距、页边距和布局等核心排版字段。文本前景色使用独立模型，避免把 JSON 调色板和词条列表塞进 `book_reading_overrides` 的排版列。

## 8. 分阶段实施计划

### Phase A：模型、迁移与设置（已完成基础范围）

1. 创建领域模型、默认调色板和 JSON 迁移；
2. 增加数据库 schema 与 Repository；
3. 完成全局总开关、token 开关、亮/暗色编辑和书籍级跟随/覆盖；
4. 单元测试默认值、旧数据加载、颜色 token 稳定性和 migration。

### Phase B：EPUB 文本类型渲染（已完成基础范围）

1. 在 runtime 中实现命名空间隔离的 CSS Highlight 管理；
2. 先接入 `latin`、`number`、`punctuation`，再接入同节点的 `quoted`、`bracketed`；
3. 验证分页、滚动、主题切换、章节切换和搜索/标注共存；
4. 在不支持 Custom Highlight 的运行环境中验证无功能退化。

### Phase C：自定义词条（已完成基础范围）

1. 在选区菜单添加“文字颜色”，完成本书/全局写入和词条管理；
2. 实现范围覆盖、最长匹配和颜色合并；
3. 加入数量/长度限制、重复词处理和批量删除；
4. 仅在 Phase B 性能达标后开放默认入口。

### Phase D：PDF 与增强

PDF 只有在文本选区、页面内坐标与全文检索稳定后才接入。应使用 pdfrx 的文本选择/绘制能力实现，不复用 EPUB 的 iframe 或 CFI 假设。后续可评估词条导入/导出、跨内联标签匹配和 AI 推荐词条，但 AI 推荐必须由用户确认后才写入。

## 9. 验收与测试

### 必须通过

- 关闭总开关后正文、分页、位置和标注行为与当前版本一致；
- 主题切换后使用对应亮/暗色，且不会遗留旧章节 highlight；
- 创建、删除或改色本书词条后不影响同名全局词条；本书规则删除后可正确回退；
- 切换分页/滚动、跳转目录、搜索、创建标注和重启应用后，定位与选区偏移保持正确；
- 无 Custom Highlight API 时应用不报错，阅读器仍可打开、搜索和标注；
- 导出的笔记与 AI 引用仅使用原始正文，不包含颜色配置或词条样式。

### 自动化测试

- Dart：设置 JSON、词条规范化、范围覆盖、Repository migration、最大数量和权限边界；
- runtime：Range 构建、嵌套/未闭合标点、命名空间清理、重叠词条与降级路径；
- 集成：EPUB 翻页/滚动/主题/搜索/标注并发切换，确认 locator 未变化；
- 性能：以长章节和上限词条集测试渲染耗时、内存和取消行为，记录 Windows 与 Android 基线。

## 10. 开发约束

1. 不复制 ColorTxt 源码或未获授权的资源；实现必须独立完成。
2. 文本着色不得修改原书文件、章节 HTML 结构或 SQLite 中的原文。
3. 所有颜色都需提供总开关和 token 级关闭能力；无障碍模式下可一键恢复单色正文。
4. 不允许用用户输入的正则表达式直接扫描章节；所有词条必须限制长度、数量并转义。
5. PDF 支持不能为了视觉一致性而绕过其定位与选区可靠性问题。
