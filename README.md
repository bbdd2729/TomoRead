# TomoRead

TomoRead 是一款基于 Flutter 构建的跨平台阅读器，面向本地书库与沉浸式阅读体验，并为 AI 问答、阅读指导和知识整理能力预留了清晰的架构扩展点。

当前版本聚焦可靠的本地 EPUB/PDF 阅读、书库管理与阅读数据持久化。AI 能力属于后续开发重点，尚未接入在线模型服务。

## 下载

前往 [Releases](../../releases) 页面下载已发布版本。发布包按平台提供：

- Windows x64：解压 ZIP 后运行 `tomoread.exe`
- Linux x64：下载并解压 `tar.gz` 包
- Android：下载并安装 APK；AAB 用于应用商店发布

## 功能

- [x] 导入与管理本地 EPUB、PDF 文件
- [x] EPUB 元数据、封面、目录与章节解析
- [x] PDF 阅读与目录导航
- [x] 桌面端与移动端自适应阅读界面
- [x] 书库搜索、筛选、分类、标签、收藏与列表/网格视图
- [x] 书籍详情页：编辑书名、作者、简介、标签与分类
- [x] 书签、高亮、笔记与阅读进度持久化
- [x] 全局与单本书阅读设置：字体、字号、行距、边距、主题与阅读方向
- [x] 沉浸式阅读模式、可收放目录/书签面板与可拖动面板宽度
- [x] EPUB 分页/滚动阅读、章节与页组导航、底部进度定位
- [x] Windows、Linux、Android 自动构建与手动发布工作流
- [ ] AI 选中文本提问与上下文对话
- [ ] AI 阅读指导、摘要、词句解释与学习卡片
- [ ] 云端同步、跨设备进度和笔记同步

## 支持平台

| 平台 | 状态 | 发布产物 |
| --- | --- | --- |
| Windows x64 | 支持 | ZIP 包 |
| Linux x64 | 支持 | `tar.gz` 包 |
| Android | 支持 | APK、AAB |
| macOS | 计划中 | - |
| iOS | 计划中 | - |

每次推送和 Pull Request 都会执行静态检查、测试及 Windows、Linux、Android 构建。手动触发 `Release` 工作流时可选择目标平台与版本号，成功后会创建对应 Git tag 和 GitHub Release。

## 架构

项目采用按职责分层的 Flutter 架构，界面状态由 Hooks Riverpod 管理，持久化使用 SQLite：

```text
lib/
├── app/        # 应用入口、主题、Provider 与全局状态
├── domain/     # 领域模型：书籍、目录、位置、书签、标注、阅读设置
├── data/       # SQLite、仓储、EPUB/PDF 导入、解析、解压与文件存储
├── features/   # 书库、书籍详情、阅读器、设置等功能界面
└── shared/     # 跨功能复用的 UI 组件与工具
```

### 数据流

1. 导入服务复制并校验原始书籍文件，解析 EPUB/PDF 元数据。
2. 仓储层将书库、阅读位置、书签、标注和设置保存到 SQLite。
3. Riverpod Provider 负责把异步数据与界面状态连接起来。
4. EPUB 在 WebView 中渲染，PDF 使用 `pdfrx` 渲染；两者共用书签、进度与阅读设置模型。
5. 后续 AI 服务将通过独立的数据/服务边界接入，不耦合到阅读器 UI 或数据库实现。

## 开发

环境要求：Flutter 3.44.8、对应平台的原生开发环境，以及 Windows/Linux 桌面构建所需工具链。

```bash
flutter pub get
flutter analyze lib test
flutter test
flutter run -d windows
```

常用构建命令：

```bash
flutter build windows --release
flutter build linux --release
flutter build apk --release
```

Android Release 构建需要配置签名。GitHub Actions 使用仓库 Secrets 中的 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS` 和 `ANDROID_KEY_PASSWORD`。

## 路线图

### 已完成

- [x] 本地书库、EPUB/PDF 导入与去重
- [x] 阅读位置、书签、笔记、标注和设置的本地持久化
- [x] 书籍详情、书库组织、阅读器工具栏与沉浸模式
- [x] 三平台 CI 构建和可选平台 Release 发布

### 近期

- [ ] 完善 EPUB 分页器：稳定的双页组、精确定位、更多 EPUB 样式兼容
- [ ] 扩展 PDF 阅读控制与可拖动进度定位
- [ ] 阅读统计、搜索结果导航与导出能力
- [ ] 完善移动端阅读交互和页面切换动画

### AI 阅读能力

- [ ] 配置模型提供商与安全的 API Key 管理
- [ ] 基于选中文本、章节和书籍元数据的 AI 问答
- [ ] 段落解释、摘要、阅读计划与学习指导
- [ ] 笔记整理、知识卡片和可控的上下文引用

### 后续

- [ ] WebDAV/云端同步与冲突处理
- [ ] macOS、iOS 支持
- [ ] 插件化的阅读格式与 AI Provider 扩展
