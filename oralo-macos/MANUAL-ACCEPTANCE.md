# Mac 0.1.0 (12) · 人工验收 / Manual acceptance

日期：2026-11-23。此候选版合并三个阶段。仅完成构建、代码检查与本地包签名校验；**本轮未运行单元、UI、语音或会议自动测试**。下列事项均等待人工验收，旧版本的测试结果不能代表本版已通过。

## 新增：使用指南（候选版 12）

1. 点击欢迎页、稿库或备稿顶部工具栏的灯泡，查看「快速上手」和「视频会议与投屏」两页；也可从系统「帮助」菜单或 Oralo 菜单栏入口打开。
2. 确认是独立的指南窗口，可用「完成」或 Esc 关闭；重开不会产生多个指南窗口，也不应改变当前讲稿或演讲状态。
3. 查看钉钉示意图：强调「应用窗口」和选择 PPT / 浏览器；全桌面、镜像、透明度及腾讯会议过滤选项的说明应容易找到。
4. 在中英文、浅深色及较窄窗口下，正文应换行完整、可滚动，底部关闭按钮始终可见。本轮只构建，未执行 UI 或会议测试。

## 1. 准备 → 排练 → 复盘 → 编辑

1. 打开已有稿件或创建语言对应的示例稿，在右上角「讲稿工具」菜单选择「开始排练」（⇧⌘R）。
2. 准备检查页确认语言、设备端识别状态和音量。未安装模型时显示下载入口；权限不可用时可以选择手动或定速，不应强制开麦。
3. 在排练页暂停、继续、上一句、下一句和点击正文；正常读几句，再自由发挥、接回原稿。结束后查看用时、暂停、手动选句和复盘线索。
4. 点击「编辑原句」，确认定位的是当前稿件中对应的句子。先改写该句后再查看旧记录，应提示手动定位，不能猜测跳到其他句子。
5. 在复盘里选择「检查是否需要注音」，回到正文选词、试听、保存。查看复盘标记；也可标记无需添加、暂时忽略或撤销标记。标记不代表自动判定发音错误。
6. 「再次排练」应使用修改后的稿件。历史记录保留当时快照；正式演讲和排练可以筛选。
7. 退出再打开，记录仍应在。关闭演讲窗口或应用结束的会话应显示未完成。普通“结束演讲”显示已完成。

## 2. 备稿与阅读工具

1. 「讲稿工具 → 分句排版」：点击句中位置拆分、合并下一句、添加读后暂停、重新分句；检查原词注音仍正确。错误拆在注音中间时应给出提示。
2. 「全部注音」：编辑与试听、切换“演讲时显示”、移除；修改已注音词语后，失效注音应提示重新关联，由你在正文选择新词。
3. 「查看初稿」应只读；「导出纯文本」（⇧⌘E）选择文件位置，导出当前正文，不混入注音或复盘信息。TXT/MD 导入保持现有能力。
4. 进入悬浮窗，切换定速模式，确认麦克风关闭。调 0.5×–2×、暂停/继续、选择句子、切回语音或手动。暂停时切换模式仍应保持暂停。
5. 在演讲页与悬浮窗之间切换，字号、行距、注音与选句位置保持合理；靠近摄像头、四角位置、尺寸、透明度和系统调色盘维持现有交互。
6. 会议前台操作悬浮控件，不应主动激活 Oralo。结束悬浮提词后，从菜单栏「查看复盘记录」进入；不会强制把复盘窗口弹到会议前面。

## 3. 偏好、数据与语言

1. 在「Oralo → 设置…」（⌘,）调整默认语言、默认语音/手动、悬浮模式、语速、外观等。退出重开后检查设置复用。
2. 调中文/英文语速后，稿库和备稿的预计时长同步变化；真实语音跟随仍由说话节奏驱动。
3. 切换系统给 Oralo 指定的英语、简体中文、繁体中文并重开；新示例稿、权限说明、错误提示及长文案布局应匹配。分别查看浅/深色。
4. 用键盘访问菜单、选项和按钮；演讲页空格暂停/继续、左右键选句。用 VoiceOver 检查新页面的标题、控件与正文朗读。
5. 查看隐私、官网、GitHub、MIT/词典许可与支持信息；复制支持信息不应包含讲稿、录音、完整转写或本地路径。
6. 最后验收数据管理。需要保留的稿件先导出：清除排练仅删排练与无引用快照；删除单稿同步删除其历史；删除全部清理稿件、初稿、注音、所有记录、快照、恢复副本和偏好。重开不能恢复已删除内容。导出文件与系统备份不在应用清理范围。

## 平台与发布边界

- 当前本地包为 Apple silicon；macOS 15 为最低部署目标。macOS 15/27、Intel、不同音频设备、多屏和真实会议表现仍需对应硬件人工验收。
- 语音识别使用现有 build 14 跟随内核和 Mac 音频适配；本轮增加被动复盘观察和独立定速时间线，没有重写匹配/延迟补偿算法。没有声称已通过本轮语音回归。
- 使用系统当前输入设备，切换在系统声音设置中进行；没有新增应用内设备选择器。
- 发布配置见 [DISTRIBUTION.md](DISTRIBUTION.md)。本轮没有归档到开发者账户、上传、公证、商店提瑞交、commit 或 push。

## English

This candidate combines readiness/rehearsal/review, preparation/reading tools, and settings/local-data/privacy work. **No automated tests ran for candidate 11.** Build and local signing checks do not establish interaction, audio, focus, deletion-recovery or accessibility correctness.

Follow the same order: **Script tools → Rehearse → review → Edit passage / Check pronunciation → rehearse again**; then sentence layout, initial draft, export and full reading management; then paced floating mode and saved preferences; finally language, appearance, accessibility and deliberate data deletion. Confirm a changed historical passage requires manual location, and ending a floating session does not bring Oralo over the meeting app.

Distribution remains separate: the default bundle is locally signed for development. No store submission, notarization, commit or push was performed.
