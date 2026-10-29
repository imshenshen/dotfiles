# Rime 架构

## 1. 构建对象

本仓库构建的是一个**定制前端 + 包内默认数据**，不是 librime fork：

- 固定上游 Squirrel 提交 `0cd71a6130a5866b0ae6ba0494929ebdc8211194`。
- 上游的 librime、Lua、Sparkle 等使用该提交下载的预编译二进制。
- 本仓库只维护前端 patch、语音桥、云候选插件、安装器辅助程序和发布默认数据。

构建链：

```text
build_squirrel.sh
├─ 反向撤销/重新应用 native/squirrel/*.patch
├─ build_voice.sh          → RimeVoice.app + libRimeVoiceBridge.dylib
├─ build_cloud_plugin.sh   → librime-cloud-pinyin.dylib
├─ xcodebuild              → Squirrel.app（arm64 + x86_64）
├─ LocalBuild.plist        → 源码提交、依赖版本、功能标记
└─ package_squirrel.sh
   ├─ build_source_recovery.sh
   ├─ prepare_release_data.sh
   ├─ sign_squirrel_app.py
   ├─ pkgbuild/productbuild
   └─ notarize_squirrel.sh → dist/Squirrel-<version>.pkg
```

`package_squirrel.sh` 可以单独重跑，但前提是 `.build/squirrel` 里已有上游 checkout、构建件和打包组件；它仍会重新签名、打包和公证。

## 2. 三层发布数据

打包不读取 `~/Library/Rime`。`prepare_release_data.sh` 是唯一合同：

1. 上游固定提交的 plum preset（提供基础方案、OpenCC、语言数据）。
2. `distribution/data/` 公共资源快照（白霜、五笔、明月等公开词库/方案；来源与授权见 `distribution/README.md`）。
3. 仓库根部的项目配置与 Lua：`default.custom.yaml`、`squirrel.custom.yaml`、`wubi86.custom.yaml`、`rime_frost.custom.yaml`、`luna_pinyin_simp.custom.yaml`、`wubi86_pinyin.schema.yaml`、`lua/wubi_pinyin_router.lua`、`lua/slash_literal.lua`。

随后写入空的 `custom_phrase.txt` 模板、`VoiceDefaults.plist`、许可文件；用 `rime_deployer --build` 预编译；删除 `installation.yaml`/`user.yaml`；拒绝 symlink、`*.userdb`、`mixed_user_dictionary.json` 和私有偏好进入发布资源。

`distribution/data` 是 2026-10-14 的冻结快照，不是实时白霜更新；更新公共词库需要单独审查体积、来源和授权。

## 3. 运行时层级

```text
Squirrel.app/Contents/SharedSupport     包内默认配置、公共词库、build/
        ↓ 被同名文件覆盖
~/Library/Rime                           用户 YAML/Lua、个人 custom_phrase、学习 userdb、sync/
        ↓ 由应用管理
OSS 加密 bundle                          固定词条、别名、热词、Rime sync 快照
```

- 新电脑只需要安装 PKG；包内默认值已经包含五笔、拼音、白霜、云候选和语音组件。
- 个人词条和热词由“用户词典”窗口和 OSS 同步管理；`mixed_user_dictionary.json`、`*.userdb`、`installation.yaml` 属于本机/用户数据，不进仓库和安装包。
- 旧机器如果还有 `~/Library/Rime/*.custom.yaml` 或 `custom_phrase.txt` 软链，会覆盖包内默认值；迁移方式是备份并移除软链（`custom_phrase.txt` 转为普通文件），再用当前 App 的 `rime_deployer --build` 重新部署。**不要在生产机器重新建立软链。**
- 仓库根 `custom_phrase.txt` 仍被 Git 跟踪，仅作为个人备份；它不是新机器的部署源，也不进入 PKG。

## 4. 原生组件

### Squirrel 前端

权威改动是 `native/squirrel/*.patch`，按以下顺序应用：

1. `cloud-badge.patch`：云候选角标和 `_refresh_ui` 协议。
2. `voice-input.patch`：语音菜单/设置/桥接入口、快捷键和输入控制器集成。
3. `pkg-only-updates.patch`：关闭 Sparkle，保留定制 PKG 更新。
4. `release-safety.patch`：安装/输入源恢复和发布安全约束。
5. `slash-commands.patch`：`/fh`、`/gif`、非激活面板和直接 ASCII 触发。

补丁只触达上游的 `resources/Info.plist`、`sources/InputSource.swift`、`sources/Main.swift`、`sources/SquirrelApplicationDelegate.swift`、`sources/SquirrelInputController.swift`、`sources/SquirrelPanel.swift` 等少量文件。不要复制整份上游源文件进仓库。

### RimeVoiceBridge / RimeVoice

`native/voice/*.swift` 编译成两个产物：

- `RimeVoice.app/Contents/MacOS/RimeVoice`：麦克风采集、Apple SpeechAnalyzer、豆包 WSS 二遍识别和音频播放测试。
- `libRimeVoiceBridge.dylib`：语音 UI/控制、共享词典、豆包词库导入/推送 UI、符号/GIF 面板、OSS 同步 UI 和状态机。

桥接库被注入 Squirrel.app；语音 helper 以独立进程运行。豆包凭证通过父子进程管道传递，不放在命令行参数、YAML 或日志里。

### 云候选

`native/cloud_pinyin/cloud_pinyin.mm` + `core.h`：轮询搜狗/Google/百度，做去重、交错排序、TTL/LRU 缓存和候选角标；前端只通过 `_refresh_ui` 刷新。具体数据和开关见 [cloud-pinyin](cloud-pinyin.md)。

### 安装与豆包 helper

- `native/installer/SourceRecovery.swift`：升级后等待 Installer 退出，恢复原鼠须管父输入源和简体/繁体模式集合；不在安装事务中程序化切换。
- `native/doubao-dictionary/doubao_push.cpp`：独立编译、ad-hoc 签名、带引擎 SHA-256 校验的外部 helper，写入豆包本地 `usr.dat`；不进入 App/PKG。构建 `tools/build_doubao_push.sh`。
- `native/signing/create_installer_csr.swift`：一次性的 Installer 证书 CSR 工具，不属于构建路径；见 [signing](signing.md)。

### 符号目录

`distribution/data/symbols.yaml` 是 `/fh` 字形来源；`tools/generate_symbol_catalog.py` 生成 `native/voice/SlashSymbolData.swift`（158 条、非 ASCII、分类/拼音/hex 搜索）。生成文件不要手改，`test_slash_palette.sh` 会跑 `--check`。

## 5. 数据流和安全边界

| 功能 | 输入 | 外发 | 本机状态 |
|---|---|---|---|
| 云候选 | 用户键入选中的拼音 | 搜狗/Google/百度 HTTPS | 进程内缓存；不持久化正文 |
| Apple 语音 | 麦克风音频 | 不上传 | helper 内存；结果写回当前输入框 |
| 豆包 ASR | 麦克风音频 | 固定 `wss://openspeech.bytedance.com/...` | Keychain 凭证；热词仅随本次请求发送 |
| 豆包重写 | 本轮识别文本 | 火山方舟/Ark HTTPS | 独立 Keychain 凭证；结果只在黑条预览 |
| 豆包词库导入 | Mac 豆包本地侧词库 | 不上传 | 只读合成预览；不写真实文件 |
| 豆包词库推送 | 选中的固定短语 | 经豆包账号上传 | helper 备份/原子替换 `usr.dat` |
| GIF | 搜索 query / 选中 GIF | Giphy/Tenor/自定义 HTTPS | 缓存 7 天/100MB；复制到系统剪贴板 |
| OSS 同步 | 固定词条/别名/热词/userdb 快照 | 阿里云 OSS `shurufa/` | AES-GCM bundle；Keychain AK/SK |

Keychain service：

- 豆包语音：`im.rime.inputmethod.Squirrel.DoubaoSpeech`
- 豆包重写：见 `VoiceRewritePreferences`
- GIF：`im.rime.inputmethod.Squirrel.GIFSearch`
- OSS：`im.rime.inputmethod.Squirrel.RimeSync`

安全不变量：

- 不把 Keychain、`release.json`、个人词条、学习库、机器身份或签名私钥写进仓库、安装包、日志和聊天。
- 云候选、豆包 ASR、重写、GIF 和 OSS 都是明确的数据外发路径；任何隐私/网络逻辑改动都要在 `security` 相关评审和人工验收中说明。
- 已知仍需关注的风险：安全输入（Secure Event Input）与云端语音/候选的边界、云服务重定向域名限制、上游 plum 资源的可复现性、发布脚本中的断言式校验。改动这些区域前先核对代码和测试，不要仅凭旧审计文档的结论。

## 6. 功能标记

`build_squirrel.sh` 把以下信息写入 `Contents/Resources/LocalBuild.plist`，是安装后判断构建能力的第一手依据：

- `UpstreamCommit`、`BuiltAtUTC`、`Architectures`、`LibrimeVersion`
- `CloudPinyinVersion=3`、`CloudBadgeUI=true`、`WubiMixedFifthCode=true`
- `VoiceInputVersion=22`、`VoiceFocusResume`、`SharedUserDictionary`、`MixedTextSpacing`、`GlobalDictation`、`DoubaoSpeechTwoPass`
- `SlashPaletteVersion=1`、`SlashPaletteNonactivating=true`、`SlashSymbolCount=158`、`GIFSearchVersion=1`、`GIFClipboardNoAutoPaste=true`
- `RimeSyncVersion=1`、`RimeSyncProvider=AliyunOSSv1`、`RimeSyncAuto=true`、`RimeSyncUserDB=RimeSyncSnapshots`
- 安装策略：`NoForcedLogout=true`、`InstallerPreservesNativeSwitching=true` 等

新增/删除功能时，同时更新 `build_squirrel.sh`、README 的当前状态、本文件或对应功能文档；否则下一位维护者会被版本号误导。
