# macOS distribution preparation

The default project remains a local development app (`com.ch563.oralo.mac.dev`). Candidate 0.1.0 (12) is for manual acceptance. No distribution certificate, provisioning profile, App Store record, notarization request or review submission is created by this work.

## Preview DMG

Candidate 0.1.0 (12) can be packaged as a universal Apple-silicon/Intel DMG for manual testing on macOS 15 or later. The package keeps the local test identifier and ad-hoc signature. It is **not Developer ID signed or notarized**; testers may need the per-app **System Settings → Privacy & Security → Open Anyway** action, after confirming the source. See [Apple’s instructions](https://support.apple.com/102445). Do not disable Gatekeeper or remove quarantine as an installation step.

The compact 620 × 440-point cream/indigo installer contains only real draggable app and Applications icons, a drag arrow and centered bilingual instructions. Its background fills the content area, with no Read Me icon or overflow scrollbars. Retina artwork and layout are generated from source. Release builds keep debug symbols in a separate dSYM and strip them from the installed executable. The helper rejects local home-directory paths and credential patterns in the app before packaging. It verifies the input signature, both executable architectures, the disk image, the packaged app signature and the destination link; it emits a SHA-256 file. It does not launch the app, run app tests, sign with another team’s identity, notarize or upload.

With Python 3.10+ and Xcode available, run from this directory (choose new temporary output paths):

```sh
xcodebuild -project OraloMac.xcodeproj -scheme OraloMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/Oralo-Universal \
  ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build
python3 -m venv /tmp/Oralo-DMG-Tools
/tmp/Oralo-DMG-Tools/bin/python -m pip install dmgbuild==1.6.7
/tmp/Oralo-DMG-Tools/bin/python scripts/package_test_dmg.py \
  --app /tmp/Oralo-Universal/Build/Products/Release/Oralo.app \
  --output-dir /tmp/Oralo-DMG-Delivery
```

Use dmgbuild 1.6.7 or newer: earlier versions write a background bookmark that [does not display correctly on macOS Tahoe 26.2+](https://github.com/dmgbuild/dmgbuild/pull/275). The script refuses to overwrite a DMG. Packaging a universal executable is not evidence of runtime acceptance on Intel or older macOS; those remain manual hardware checks.

## 预览版安装包

当前 DMG 是未公证的测试预览包，保留本地测试 Bundle ID，不含开发者的讲稿或设置。拖入「应用程序」后从该目录启动，首次打开若被阻止，确认来源可信后在「系统设置 → 隐私与安全性」选择「仍要打开」。安装窗口不再放置 Read Me 入口。只采用系统提供的单应用确认方式，不关闭系统安全保护。正式对外发行仍需 Oralo 团队自己的 Developer ID 签名、公证和干净设备验证。

## Decide before distribution

- **Mac App Store**: choose whether to add macOS to Oralo’s existing app as a universal purchase or use a separate app record. A shared purchase changes the product’s commercial relationship with the iOS app; this is an owner decision, not a build setting to guess. Configure the corresponding identifier and provisioning in the developer account first.
- **Direct distribution**: choose a distribution identifier and Developer ID signing. Keep app sandbox, audio-input and user-selected read/write entitlements. Direct distribution needs its own purchase/update delivery decision; none is implemented here.

Changing the bundle identifier produces a separate sandbox. This local candidate does not silently migrate or overwrite the existing iOS app’s data or a future distribution app’s container.

## Archive configuration

`Configurations/Distribution.xcconfig` is opt-in. The normal local build never loads it. With the selected identity/profiles installed in Keychain, invoke:

```sh
ORALO_TEAM_ID=YOURTEAMID ORALO_BUNDLE_ID=com.example.chosenidentifier \
  scripts/archive_distribution.sh developer-id /absolute/output/Oralo.xcarchive
```

Use `mac-app-store` for a store archive. The script refuses missing IDs, the local dev identifier and an existing output archive. It performs an archive build only; it does not enable automatic account/provisioning changes, export, notarize, upload or submit. Credentials belong in Keychain or environment configuration, never this repository.

After manual acceptance, use Xcode Organizer for the selected distribution route. Direct distribution additionally requires successful notarization, stapling and Gatekeeper verification on a clean Mac. Store distribution needs the final app record, metadata, privacy answers, screenshots and review notes. These steps remain pending owner authorization and the choice above.

## Prepared in this candidate

- macOS 15 deployment target; guarded macOS 26 speech and Liquid Glass APIs.
- Local and distribution identifiers separated; Release builds use hardened runtime and sandbox.
- Only microphone and user-selected file read/write access. Export is via the native Save panel. No camera, screen-recording or Accessibility entitlement is added.
- English, Simplified Chinese and Traditional Chinese microphone/speech permission descriptions.
- Privacy manifest declares app-only preferences and elapsed-time timers (`35F9.1`); see [Apple’s reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons). No boot-time value is included in support details.
- Local-data disclosure, support/GitHub links and MIT/dictionary licenses included.
- No account, advertising, analytics, raw audio storage or full-transcript archive.

See [Apple’s privacy manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) when checking the final distribution archive. Build success is not a claim of signing, notarization or App Review acceptance.

## 人工发布前确认

当前只生成本地候选包。先验收准备检查、排练复盘、备稿工具和数据删除，再确认 Mac App Store 通用购买或独立发布路线。归档脚本不上传、不公证、不提交审核；正式证书、商品关联、商店资料和分发流程仍需按最终渠道配置。
