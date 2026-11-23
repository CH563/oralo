# Oralo for macOS

[简体中文](#简体中文) · [Website](https://oralo.fun) · [MIT license](../LICENSE)

Native macOS preparation, presentation and floating prompting. This is a local development build, separate from the validated iOS build 14. Minimum deployment target: macOS 15; on-device speech availability depends on hardware, language and installed system models. Candidate **0.1.0 (12)** combines the three parity stages and awaits [manual acceptance](MANUAL-ACCEPTANCE.md). This round ran build checks only, with no automated tests. See [historical validation](VALIDATION.md).

## Build and run

Requires Xcode 26 or later with Swift 6.2 or later. Open `OraloMac.xcodeproj`, select **OraloMac → My Mac**, and run. The default identity is **Sign to Run Locally**; no development team, credentials or App Store changes are needed.

```sh
xcodebuild -project OraloMac.xcodeproj -scheme OraloMac \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/Oralo.app
```

The bundle identifier `com.ch563.oralo.mac.dev` is for local validation. Opt-in [distribution archive configuration](DISTRIBUTION.md) is prepared. Distribution signing, universal purchase and App Store submission remain separate owner decisions.

For a drag-to-install package for other Macs, see [Preview DMG](DISTRIBUTION.md#preview-dmg). The current test package is universal and unnotarized; first-launch guidance is documented with the packaging instructions.

## Included

- A lightbulb in the top toolbar opens a native User Guide window, also available from Help and the menu-bar menu. Two pages cover getting started and using a floating prompt in video calls. A bilingual vector example highlights DingTalk’s App window casting option, explains choosing slides or a browser, and asks the speaker to check the actual shared preview. The guide distinguishes window sharing from desktop sharing/mirroring and explains that transparency does not exclude a window from capture. It does not change audio, following or meeting settings.

- A concise, optional welcome page, then a standalone script library with persistent grid/list layout and title/body search. Only opening or creating a script enters the split editor. Returning to the library flushes pending edits.
- Native macOS toolbar controls, menu commands and shortcuts (⌘N, ⌘O, ⌘F, ⌘S, ⇧⌘L). Settings live in **Oralo → Settings…** (⌘,). macOS 26+ uses system Liquid Glass; macOS 15 keeps native fallback controls.
- New script, TXT/MD import, language-matched sample, editing, autosave, explicit save and document undo.
- The preparation bar starts with a compact speech-language menu, followed by native left/center/right alignment controls. Whole-script alignment is a local reading preference shared by preparation, presentation and floating windows, and is restored on relaunch. It does not insert spaces or change manuscript text or pronunciation anchors.
- Selected-word pinyin / IPA lookup, manual correction, system pronunciation playback, persistent occurrence anchors and ruby text above the original words.
- A native reader with word/character highlighting, upper reading focus, pause/resume, sentence navigation, off-script hold and recovery, mirror, full screen and appearance preferences. Neutral glass controls float over the script; narrower windows use symbols, with accessible labels and tooltips. Controls remain available while paused, adjusting settings or using VoiceOver.
- A nonactivating floating panel with a direct near-camera button, draggable status header, corner resize, a native three-size segmented picker and live dimensions. Text size and 0–80% background transparency update immediately; only the background fades. Position is saved and recovered after display changes.
- Floating appearance includes 0–24 pt of extra line spacing, five light/dark-aware highlight presets and a custom opaque sRGB color through the system color palette. The custom swatch reflects the picked color. Both presentation and floating settings offer size, spacing, color, appearance and mirror shortcuts; the readers keep separate font/spacing preferences and share their palette. Changes apply immediately and persist locally.
- Floating settings are compact, without inline footnotes or scrollbars. Size presets and dimensions share one row; near-camera and four corner buttons place the window within the current screen. Settings use a separate nonactivating panel. Close settings with its close button, the settings button again, or Escape.
- All app preferences are stored locally: appearance, welcome page, library layout, each reader’s text size and spacing, highlight preset/custom color, mirror, transparency, floating frame and compatibility recognition. The system color-panel mode is also remembered. Speech language remains part of each saved manuscript.
- One speech session shared between presentation and floating windows. Resizing or switching these windows does not recreate recognition or reset the cursor.
- Visible capture state, explicit end-session control and menu-bar pause/resume. Oralo does not mute or change the microphone settings of a meeting app.

### Three-stage candidate

- **Readiness → rehearsal → review → edit**: check on-device model/permissions and microphone level; start voice, manual or paced prompting. Rehearsal and presentation history stores time, pauses, manual cue changes and passive review observations alongside the saved manuscript version. Historical passages map back only when the identity is safe; edited/ambiguous passages require manual location. Pronunciation review is the speaker’s decision, not automatic grading.
- **Preparation tools**: split/merge sentences, pause points, rebuild layout, read-only initial draft, plain-text export, a complete pronunciation list, per-reading display visibility and manual reattachment of stale hints. Reading preferences set new-script language, starting modes and Chinese/English estimated rates. Floating paced reading has a separate clock and 0.5×–2× speed; it never opens the microphone.
- **Settings and local data**: native General/Reading/Local Data/Privacy tabs; clear rehearsal history, delete a script with its history, delete all app data and recovery copies, and reset reading preferences. An interrupted deletion resumes before normal loading; old writers cannot resurrect removed data. MIT and dictionary notices, website/support/source links and text-free support details are included. English, Simplified and Traditional Chinese follow the system’s app language.

The Mac uses the system's current audio input. Change it in System Settings; an audio route change pauses recognition and keeps the script position. No in-app device picker is added. Finishing a floating prompt while another app is active leaves review available through the menu bar without activating Oralo. A reader session ended while Oralo is active opens review.


## Architecture and privacy

`OraloCore` is referenced in place from `../oralo-ios/Packages/OraloCore`; the iOS target and core sources are unchanged. `FollowEngine`, `ReadingCursor`, transcript windowing, pronunciation anchors and the library's deletion-safe persistence are reused.

The Mac speech adapters preserve build 14's fast partial results, bounded delay compensation, evidence-based recovery and 50 ms display updates. They use macOS `AVAudioEngine`, without iOS `AVAudioSession`. On macOS 26+, `SpeechAnalyzer` is used; the explicit compatibility mode uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. Unsupported on-device recognition stays paused and offers manual selection instead of silently using server recognition.

Scripts, readings, session records and revision snapshots stay in the app's local Application Support directory. Raw audio and full transcripts are not saved. Downloading an Apple speech model requires the user's explicit action in the app. Pronunciation dictionary license notices are bundled in Resources. Playback speaks the original word using a system voice; it does not claim to synthesize arbitrary custom IPA.

The floating panel uses public AppKit `NSPanel` APIs and background-only alpha. The custom swatch opens Apple’s `NSColorPanel`, created with the nonactivating style from initialization; this avoids the default color-well popover bringing Oralo to the foreground when a swatch is selected. No camera, screen recording or Accessibility permission is requested by Oralo for prompting. Whole-screen sharing can include the prompt. Floating over every third-party full-screen configuration is not guaranteed solely by an API flag and needs software/device validation.

## Earlier test suites

Candidate 11 intentionally did **not** run these suites. The UI fixtures predate the new readiness screen and need adaptation before a future automated pass; historical test results below are not acceptance of the new workflows. Use [manual acceptance](MANUAL-ACCEPTANCE.md) for this delivery.


```sh
xcodebuild -project OraloMac.xcodeproj -scheme OraloMac \
  -destination 'platform=macOS' -derivedDataPath DerivedData test
swift test --package-path ../oralo-ios/Packages/OraloCore
```

Unit tests cover camera geometry / external-display recovery, import and native text / IME input, long-document layout, pronunciation edit-save-reopen, deletion without backup resurrection, build 14 recovery and rejection of stale recognition callbacks. UI tests use isolated libraries and a debug-only silent mode; they do not measure real recognition latency or a remote participant's audio. The separate hardware test is opt-in via `TEST_RUNNER_ORALO_VALIDATE_LIVE_AUDIO=1`; it opens Tencent Meeting without creating or joining a meeting.

The opt-in hardware suite additionally runs 180 seconds of real on-device capture followed by a 15-second restart. It checks incoming audio buffers and capture state, retaining only counters. Use a quiet, non-sensitive test environment. The foreground-control UI test clicks observed screen coordinates through the meeting's menu-bar coordinate space; it does not activate Oralo before clicking its controls.

Project file regeneration, if adding/removing files: `python3 scripts/generate_project.py`. This changes only the Mac project; no third-party project-generation package is required. The generated project is checked in as source when the owner chooses to commit.

Brand assets use the approved iOS icon. Regenerate the Mac `.icns` packaging and the one-color vector menu-bar mark with `swift scripts/generate_icons.swift`, then regenerate the project. The menu-bar mark uses a filled paper silhouette with transparent quotation marks and reading lines. It is a template image, so the system adapts it to light and dark menu bars.

## 简体中文

当前候选版 **0.1.0 (12)** 已合并三个阶段：准备检查与排练复盘、备稿与阅读工具、设置与本机数据管理。按用户要求本轮只做构建与本地签名检查，没有运行自动测试；请按 [人工验收清单](MANUAL-ACCEPTANCE.md) 试用。原生 Mac 基础流程与 iOS build 14 的共享跟随内核继续保留。

- 右上角「讲稿工具」可排练、查看本稿记录、管理全部注音、分句排版、看初稿和导出正文。
- 复盘区分排练与正式演讲；支持回到原句编辑、人工读音检查和再次排练。旧句改动时不猜测定位。
- 悬浮窗增加定速模式和倍率；默认语言、方式、估算语速等偏好保存复用。
- 系统「设置」补齐数据统计、清除排练、删除全部、恢复默认、隐私、开源许可和支持入口；界面与示例支持简体/繁体中文和英文。
- [发布配置](DISTRIBUTION.md) 已准备，尚未选择最终商店/直发渠道，未上传、公证或提交审核。

- 启动先显示简洁欢迎页，可取消「启动时显示欢迎页」。稿库支持平铺 / 列表和标题 / 正文搜索，进入新建或编辑后才显示左右分栏。
- 操作集中在原生工具栏，设置从左上角「Oralo → 设置…」或 ⌘, 打开。⌘F 搜索、⇧⌘L 返回稿库；返回前会完成保存。
- 备稿操作栏的语言下拉框左对齐，不显示额外标签；读音操作左侧提供原生左 / 中 / 右对齐按钮。对齐是整篇正文的本机阅读偏好，备稿、演讲与悬浮窗共用，重启后复用；不会向原文插入空格或改变注音锚点。
- 初次开讲按需申请麦克风权限；旧识别后端还需要系统语音识别权限。
- 若缺少设备端模型，可主动下载；不支持时仍可手动选句。
- 窗口默认 520 × 240 pt、28 pt 正文、35% 背景透明度。顶部可一键靠近摄像头，拖动声波区域移动窗口，拖动右下角缩放；调整面板提供三档尺寸、实时尺寸读数、字号和背景透明度。仅背景变淡，文字保持清晰；开启系统“降低透明度”时使用不透明背景。
- 悬浮设置新增 0–24 pt 附加行距；靛蓝、蓝、绿、琥珀、玫红五种高亮色适配浅深色，自定义色直接打开系统调色盘，选色后色块随之变化。演讲页也有字号、行距、颜色、外观与镜像快捷设置；两种窗口字号和行距各自保存，高亮色共用。
- 悬浮设置去掉说明行与滚动条，尺寸选择与读数放在同一行；支持靠近摄像头、左上、右上、左下、右下五个快捷位置。
- 悬浮时可切换到腾讯会议；Oralo 暂停与会议静音互不关联。请分别验证 Oralo 收音和会议人声，不能用窗口仍可见代替声音验证。
- 外观、欢迎页、稿库布局、两种窗口的字号与行距、预设与自定义高亮色、镜像、透明度、悬浮窗尺寸和位置、兼容识别模式及调色盘模式均保存在本机，下次使用自动复用；演讲语言随每篇讲稿保存。
- 调整大小或切换演讲 / 悬浮时沿用同一个会话；退出演讲会停止麦克风。
- 注音不会混入正文识别。文本编辑保留未受影响的词语范围，覆盖到注音原词的修改会将它标记为需核对。
- 共享整个屏幕时可能包含提词窗，建议根据会议软件实际预览选择共享目标窗口。

本阶段不包含完整排练复盘、Mac/iPhone 自动同步或内置录制。不修改 iOS build 14，不自动提交审核、commit 或 push。
