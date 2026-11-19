# Oralo for iOS

Native SwiftUI app for **Oralo — AI Teleprompter, at Your Pace**. 中文名称：**接着讲 — 跟随你的 AI 提词器**。

See the [project README](../README.md) for privacy, build requirements, and the license.

## Use the app / 使用流程

1. Create a script, paste text, or import a plain-text file. The built-in sample is available for trying the flow. 新建、粘贴或导入纯文本讲稿，也可以使用内置示例。
2. Select Chinese text or an English word in the editor to add pinyin or IPA. Listen to an English word, confirm the reading, and save. 在备稿页选词添加拼音或音标，英文可试听，确认后保存。
3. Choose **Rehearse** in the script menu, or use the main presentation button. Run the readiness check when you want voice following; manual reading remains available. 在讲稿菜单选择排练，或点开讲；语音跟随前执行准备检查，也可手动开始。
4. Read at your own pace. Pause, speak freely, and return to your script; use manual cue selection when needed. 阅读时可停顿、自由发挥后接稿，必要时手动选句。
5. Finish the session to review its duration and cue events. Open a passage to inspect the saved version and edit the corresponding sentence in the current script. 结束后查看时长与句子事件，从历史片段返回当前讲稿对应原句编辑。

Historical passages are read-only. If the original sentence has changed or its identity is ambiguous, the app does not guess a new edit location or overwrite the current script. Historical events describe session activity; they are not an accuracy score or a judgment that you forgot words.

历史片段只读；原句已修改或无法确定对应关系时，不猜测编辑位置，也不覆盖当前讲稿。复盘事件仅描述过程，不代表演讲评分或忘词判断。

## Build and test / 构建与测试

Verified with Xcode 27.1. Swift language mode is 6; the core package requires Swift tools 6.2 or later. The deployment target is iOS 18.0. All source and pronunciation resources needed to build are included.

已使用 Xcode 27.1 验证；Swift 语言模式为 6，核心包需要 Swift tools 6.2 或更高版本，最低部署目标为 iOS 18.0。构建所需源码与读音资源均已包含。

Open `Oralo.xcodeproj`, choose **Oralo**, and run on a simulator. For physical devices, choose your own team and bundle identifiers in Xcode for the app and UI test targets.

From the repository root / 从仓库根目录运行：

```sh
swift test --package-path oralo-ios/Packages/OraloCore

xcodebuild -project oralo-ios/Oralo.xcodeproj \
  -scheme Oralo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For UI tests, use **Product → Test** in Xcode with an installed iPhone simulator. The shared scheme includes `OraloUITests`. Tests use isolated script libraries; deterministic speech fixtures are enabled only in Debug builds. Real microphone latency and recovery after speaking freely must be tested on a physical iPhone.

UI 测试可在 Xcode 选择已安装的 iPhone 模拟器后执行 **Product → Test**。共享 scheme 已包含 OraloUITests；测试使用独立稿库，确定性语音回放仅在 Debug 中启用。真实收音延迟与自由发挥后接稿效果需在 iPhone 上验证。

## Source map / 源码导航

| Location | Purpose / 用途 |
| --- | --- |
| [Oralo/App](Oralo/App/) | App entry and welcome flow / 应用入口与欢迎页 |
| [Oralo/Library](Oralo/Library/) | Script library, import, editing, and saving / 稿库、导入、编辑与保存 |
| [Oralo/Speech](Oralo/Speech/) | Microphone capture and on-device recognition / 麦克风采集与设备端识别 |
| [Oralo/Prototype](Oralo/Prototype/) | Reading UI, follow integration, and optional diagnostics / 提词界面、跟随集成与诊断 |
| [Oralo/Pronunciation](Oralo/Pronunciation/) | Pinyin, IPA lookup, inline layout, and playback / 拼音、音标查询、注音排版与试听 |
| [Oralo/Rehearsal](Oralo/Rehearsal/) | Readiness, session recording, review, and edit navigation / 准备检查、过程记录、复盘与编辑定位 |
| [Packages/OraloCore](Packages/OraloCore/) | Matching, reading state, document models, local persistence, and core tests / 匹配、阅读状态、稿件模型、本地存储与核心测试 |
| [OraloUITests](OraloUITests/) | Welcome, library, reading, pronunciation, and rehearsal flows / 欢迎、稿库、提词、注音与排练流程测试 |

## Speech and storage / 语音与存储

- On supported iOS 26+ devices, `SpeechAnalyzer` and `SpeechTranscriber` process speech on device. Model downloads require an explicit action. iOS 26 及以上在支持的设备使用新语音接口，下载模型需用户主动操作。
- The compatibility path checks `supportsOnDeviceRecognition` and sets `requiresOnDeviceRecognition = true`. It does not fall back to server recognition. 兼容路径检查设备端能力并强制本地识别，不回退到服务器识别。
- Chinese readings use Foundation transliteration and can be corrected. English IPA uses a bundled dictionary; playback uses `AVSpeechSynthesizer` and is an example of the word, not synthesis of edited IPA. 中文采用可校正的系统转写；英文使用内置音标词典，试听为系统单词发音，不是对手工音标的合成。
- Scripts, pronunciation notes, rehearsal snapshots, and recovery copies are saved in the app's local storage. Raw audio is not written to files; recognition text is used in memory. 讲稿、注音、排练快照与恢复副本保存在本机；原始音频不写入文件，识别文本在内存中使用。
- Readiness checks do not advance the script or contribute to session duration. Rehearsal persistence runs independently of microphone capture. 准备检查不推进讲稿、不计入排练时长；过程保存与麦克风采集分离。

The full data-handling description is in the [project README](../README.md#privacy--隐私). Third-party pronunciation notices are included in [Resources](Oralo/Pronunciation/Resources/).
