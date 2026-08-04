# TomoRead

[![CI Build](https://github.com/bbdd2729/TomoRead/actions/workflows/ci.yml/badge.svg)](https://github.com/bbdd2729/TomoRead/actions/workflows/ci.yml)
[![Release](https://github.com/bbdd2729/TomoRead/actions/workflows/release.yml/badge.svg)](https://github.com/bbdd2729/TomoRead/actions/workflows/release.yml)

> Licensed under the [GNU General Public License v3.0 only](LICENSE).

TomoRead 是一款基于 Flutter 的跨平台 AI 阅读器，面向本地 EPUB/PDF 书库、沉浸式阅读、全局知识整理和基于原文的 AI 对话。

项目目前以 Windows 和 Linux 桌面端为主要开发目标。书籍、阅读位置、书签、标注、笔记、对话和阅读统计默认保存在本地；模型 API Key 通过系统安全存储管理。使用 AI 功能时，用户输入和明确附加的原文会发送到所配置的模型服务商。

## 下载

前往 [GitHub Releases](https://github.com/bbdd2729/TomoRead/releases) 下载已发布版本：

- Windows x64：下载 ZIP，解压后运行 `tomoread.exe`
- Linux x64：下载并解压 `tar.gz`，运行 bundle 中的 TomoRead
- Android：实验性支持；APK 分为 `armeabi-v7a`（32 位 ARM）和 `arm64-v8a`（64 位 ARM），AAB 用于应用商店

> TomoRead 仍在积极开发中。升级前建议保留重要笔记的 Markdown 或 JSON 导出文件。

## 当前能力

### 阅读器

- [x] 本地 EPUB、PDF 导入、文件哈希去重与托管存储
- [x] EPUB 元数据、封面、目录、阅读顺序与章节资源解析
- [x] EPUB 分页和滚动模式、单栏/双栏排版、滚轮与点击翻页
- [x] PDF 渲染、目录导航和阅读位置保存
- [x] 沉浸式阅读，工具栏和目录/书签浮层不会挤压正文
- [x] 桌面端可拖动侧栏宽度，移动端使用抽屉和底部面板
- [x] 全局阅读设置与单本书覆盖设置
- [x] 字体、字号、行距、页边距、配色、阅读方向和翻页方式
- [x] EPUB/TXT 文本前景色：英文、数字、标点、引号/括号内容及全局/单书自定义词条
- [x] 书签、高亮、彩色标注、笔记及自定义文本选择菜单
- [x] PDF 选区标注、笔记与 AI 引用
- [x] EPUB 脚注/图片查看、安全外链策略、系统 TTS 与自动滚动
- [x] 番茄专注与阅读统计

### 书库与知识整理

- [x] 网格/列表书库、搜索、格式筛选、分类、标签与收藏
- [x] 批量收藏、分类和删除
- [x] 书籍详情页以及书名、作者、简介、分类、标签编辑
- [x] 全局笔记页：全文搜索、书籍/颜色/标签筛选与排序
- [x] 笔记 Markdown 编辑、预览、自动保存和原文定位
- [x] 笔记导出为 Markdown 或 JSON
- [x] 阅读统计：日/周/月/年/全部、阅读时长、活跃天数、连续阅读和书籍排行

### AI 阅读

- [x] OpenAI 兼容接口配置和模型切换
- [x] API Key 使用系统安全存储，不写入 SQLite
- [x] 通用对话与单本书对话持久化
- [x] 流式回复、停止生成、Markdown 展示与失败恢复
- [x] 选中文本后询问、解释或总结，并保存可跳回原文的引用
- [x] 可信内容分块、关键词与向量混合语义检索、防剧透阅读上下文
- [x] Agent 工具调用、思考摘要、技能与结构化消息 Part
- [ ] 阅读计划、学习卡片和笔记自动整理
- [ ] 更多模型协议与本地模型接入

## 支持平台

| 平台 | 状态 | Release 产物 |
| --- | --- | --- |
| Windows x64 | 主要支持 | ZIP |
| Linux x64 | 支持 | `tar.gz` |
| Android | 实验性，正在修复构建与性能问题 | v7a APK、v8a APK、AAB（可选） |
| macOS | 计划中 | - |
| iOS | 计划中 | - |

每次推送和 Pull Request 会执行静态分析与测试，并运行配置中的平台构建。手动执行 `Release` 工作流时可以选择 Windows、Linux、Android 中的任意组合。

## 技术架构

项目使用 Hooks Riverpod 管理状态，使用 SQLite 保存结构化业务数据，使用系统安全存储保存模型密钥。功能按 UI、领域模型和数据访问职责拆分：

```text
lib/
├── app/                    # 应用入口、主题、全局 Provider
├── domain/models/          # 书籍、定位、标注、对话、阅读活动等领域模型
├── data/
│   ├── database/           # SQLite schema 与版本迁移
│   ├── repositories/       # 书库、标注、对话、统计等数据访问
│   └── services/           # 导入、EPUB、AI、导出与阅读活动追踪
├── features/
│   ├── library/            # 书库与书籍详情
│   ├── reader/             # EPUB/PDF 阅读工作区
│   ├── chat/               # AI 对话
│   ├── notes/              # 全局笔记
│   ├── statistics/         # 阅读统计
│   ├── settings/           # 软件与阅读设置
│   └── workspace/          # 响应式桌面/移动导航壳
└── shared/                 # 跨功能复用组件
```

### 关键数据流

1. 导入服务复制书籍到应用目录，计算哈希并解析 EPUB/PDF 元数据。
2. Repository 将书库、阅读位置、书签、标注、对话和阅读会话写入 SQLite。
3. Riverpod Provider 将异步仓储和服务组合为页面状态，Widget 只处理展示与交互。
4. EPUB 使用内置 Foliate.js runtime 在 WebView 中渲染，PDF 使用 `pdfrx`；渲染器通过统一的定位模型与 Flutter 侧交互。
5. 阅读器将有效前台阅读活动写入会话表，统计服务再按日期和书籍聚合。
6. AI Gateway 通过 OpenAI 兼容 SSE 接口流式返回内容，对话与引用独立持久化。

更多项目文档位于 [`docs/`](docs/)：

- [核心架构](docs/architecture.md)：本地数据、AI 对话、全局笔记与阅读统计的边界。
- [阅读能力与数据边界](docs/reader-features.md)：当前格式能力、定位、标注、显示投影与内容安全规则。
- [产品路线图](docs/roadmap.md)：以 ColorTxt、ReadAny 为参照的后续优先级与交付原则。

## 本地开发

当前 CI 使用 Flutter `3.44.8`。准备对应平台的 Flutter 原生工具链后执行：

```bash
flutter pub get
flutter analyze lib test
flutter test
flutter run -d windows
```

桌面端构建：

```bash
flutter build windows --release
flutter build linux --release
```

Android 当前为实验性平台：

```bash
flutter build apk --debug
```

## 发布流程

1. 打开仓库的 **Actions > Release > Run workflow**。
2. 填写 `x.y.z` 格式版本号，例如 `0.2.0`，不要填写前导 `v`。
3. 选择需要构建的平台。Android 默认关闭，不影响桌面版本构建。
4. `publish_release=false` 时只生成 Actions Artifacts，不创建 tag 或 Release，适合测试正式构建。
5. `publish_release=true` 时，工作流会在构建成功后创建 `v0.2.0` 形式的 Git tag 和同名 GitHub Release，并上传全部所选平台产物。
6. 发布模式下，已经存在的 tag 不会被覆盖；失败修复后，如果 tag 尚未创建，可以使用相同版本重新运行。仅构建模式可以重复使用任意合法版本号。

选择 Android 构建时，需要在仓库 Secrets 中配置：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Android 会生成以下产物：

- `TomoRead-x.y.z-android-armeabi-v7a.apk`
- `TomoRead-x.y.z-android-arm64-v8a.apk`
- `TomoRead-x.y.z-android.aab`

## 路线图

### 已完成

- [x] 本地 EPUB/PDF 书库与书籍详情
- [x] EPUB 分页/滚动阅读和 PDF 阅读
- [x] 阅读位置、书签、标注、笔记和设置持久化
- [x] 全局笔记、筛选、编辑、导出和原文跳转
- [x] 阅读活动采集与多维统计页面
- [x] OpenAI 兼容 AI 对话、原文引用、Agent 工具与安全密钥存储
- [x] EPUB/TXT 文本 token 与自定义词条前景色（亮/暗色板、单书覆盖）
- [x] 系统 TTS、自动滚动、PDF 选区标注、备份/恢复与存储诊断
- [x] 内容分块、关键词与向量混合语义检索、词云与 AI 思维导图
- [x] 同步数据模型（版本、墓碑、冲突）与设置中心
- [x] Windows/Linux 构建与可选平台 Release 工作流

### 近期

- [ ] 继续提高复杂 EPUB 的分页、定位和样式兼容性
- [ ] 完善 Android 构建、WebView 渲染与低端设备性能
- [ ] 增加统计导出、阅读目标和更丰富的趋势分析
- [ ] 完善 AI 上下文选择、会话管理和错误诊断

### 后续

- [ ] WebDAV/云端同步（数据契约已就绪，缺远端传输层）
- [ ] 整章/整书检索增强、阅读指导和知识卡片
- [ ] macOS、iOS 支持
- [ ] 可扩展的阅读格式和 AI Provider 接口
