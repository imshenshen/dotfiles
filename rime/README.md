# 鼠须管定制版（Rime / Squirrel）

这是本仓库维护的 macOS 鼠须管构建：固定上游 Squirrel，加自己的前端补丁、语音桥、云候选、符号/GIF 面板和加密词库同步。所有可分发默认值都进入安装包，部署机不再依赖 dotfiles 软链。

## 当前状态

- 最新构建：`Squirrel-20261028.161100.pkg`，SHA-256 `34c64edb6c038c4043b799bd8dc7ddf7a6f7decbe6fe005398b9b0d656d37017`
- 已通过 Developer ID 签名、Apple 公证 `2f9f0428-0e58-4f92-9cc5-ceae514b1ad7`、票据装订和 Gatekeeper
- jdmbp14/jdmbp16 已迁移到包内配置并完成临时目录 OSS 双机测试；两台机器的最终安装、Keychain 保存和真实个人词库/Rime userdb 跨机合并仍需人工验收
- 工作树可能领先于已安装版本。排查时先读 `/Library/Input Methods/Squirrel.app/Contents/Resources/LocalBuild.plist`，不要只信文档里的包号

## 快速命令

```sh
# 主离线回归（含语音、词典、符号/GIF、OSS 同步、云插件核心、Doubao 状态解码）
bash rime/tools/test_voice_preferences.sh

# 只验证符号目录与 Rime 配置
bash rime/tools/test_slash_palette.sh
python3 rime/tests/verify_slash.py "/Library/Input Methods/Squirrel.app"

# 完整构建、签名、公证和打包（需要 Xcode 26、证书、notary profile）
bash rime/tools/build_squirrel.sh

# 已有构建件时只重新打包
bash rime/tools/package_squirrel.sh

# 本机安装（会备份 Squirrel.app 和 ~/Library/Rime）
bash rime/tools/install_squirrel.sh
```

详细说明见 [构建与发布](docs/build.md) 和 [测试](docs/testing.md)。

## 目录职责

| 路径 | 角色 |
|---|---|
| `default.custom.yaml`, `squirrel.custom.yaml` | 全局 Rime/Squirrel patch |
| `wubi86.custom.yaml`, `wubi86_pinyin.schema.yaml` | 五笔+拼音混输、云候选、直接 ASCII |
| `rime_frost.custom.yaml`, `luna_pinyin_simp.custom.yaml` | 白霜/明月方案的包内 patch |
| `lua/` | `wubi_pinyin_router.lua` 混输路由、`slash_literal.lua` 直接 ASCII |
| `distribution/data/` | 冻结的公共方案/词库资源快照；打包时覆盖上游 preset |
| `distribution/scripts/`, `Distribution` | PKG 安装策略和输入源恢复 |
| `native/squirrel/*.patch` | 对固定上游提交的前端补丁，按顺序应用 |
| `native/voice/` | RimeVoice helper + `libRimeVoiceBridge.dylib`；语音、词典、符号/GIF、OSS 同步 UI |
| `native/cloud_pinyin/` | 搜狗/Google/百度云候选插件 |
| `native/installer/SourceRecovery.swift` | 首次安装/升级后的输入源恢复辅助程序 |
| `native/doubao-dictionary/doubao_push.cpp` | 独立的豆包词库推送 helper（不进 App/PKG） |
| `tools/` | 构建、签名、安装、测试和诊断脚本；见 [tools/README.md](tools/README.md) |
| `tests/` | Swift/Python 回归、隔离 librime harness、手动验证器 |
| `.build/` | 本地构建缓存和签名配置（Git 忽略，不要提交） |
| `dist/` | 已生成的 PKG、公证记录和 SHA（Git 忽略，不要提交） |

## 三层发布数据

1. 上游固定提交的 plum preset（提供本仓库没有的基础方案、OpenCC 和语言数据）。
2. `distribution/data/` 公共资源快照和 `distribution/VoiceDefaults.plist`。
3. 仓库根部的项目 YAML/Lua。

`tools/prepare_release_data.sh` 是唯一打包合同：它复制并覆盖上述三层，写入空个人词典模板，预编译 Rime 数据，移除 `installation.yaml`/`user.yaml`，并拒绝 symlink、userdb、混合词典和私有偏好进入包内。详细架构见 [architecture](docs/architecture.md)。

运行时优先级为：App 内 `SharedSupport` 默认值 → `~/Library/Rime` 用户覆盖 → OSS 管理的个人词条和学习快照。生产机器不要再用 `custom_phrase.txt` 软链；旧机器迁移方法见 [sync](docs/sync.md)。

## 开发方向

- 保持上游 Squirrel 可复现构建，不维护远端 fork；原生前端改动只通过 `native/squirrel/*.patch`。
- 五笔优先、短拼音混输、第五码顶字和云候选共存；默认右 Option 启动语音。
- Apple 本地识别和豆包二遍并存；凭证只在 Keychain；失败不静默切换云服务。
- 符号/GIF 面板不抢焦点；GIF 只复制，不自动粘贴。
- 多 Mac 个人词条、语音别名、热词和 Rime 学习快照通过 OSS 加密同步；个人数据不进 PKG/Git。
- 任何涉及 IMK、麦克风、GIF 粘贴、安装器或 OSS 双机的改动，都必须保留人工桌面验收步骤。

## 文档索引

**先读（开发者/agent）**

- [AGENTS.md](AGENTS.md)：修改路径、禁区、测试和完成标准
- [architecture](docs/architecture.md)：源码权威位置、补丁顺序、数据流、安全边界
- [build](docs/build.md)：构建、签名、公证、打包、安装、回滚
- [testing](docs/testing.md)：主测试、专项测试、实时测试和人工验收矩阵

**功能**

- [voice-input](docs/voice-input.md)
- [doubao-speech](docs/doubao-speech.md)
- [doubao-dictionary](docs/doubao-dictionary.md)
- [cloud-pinyin](docs/cloud-pinyin.md)
- [slash-palette](docs/slash-palette.md)
- [sync](docs/sync.md)

**发布与参考**

- [signing](docs/signing.md)：证书、notary profile、签名故障
- [distribution/README.md](distribution/README.md)：包内公共资源来源和授权
- [tools/README.md](tools/README.md)：脚本地图

## 不变量

- `rime/custom_phrase.txt` 仍是 Git 跟踪的个人备份，但运行时由本机文件和 OSS 同步管理；不要把它当作新机器的部署方式。
- 不把 Keychain、`release.json`、用户词库、学习数据库、机器身份或签名私钥写入仓库、日志和安装包。
- 不强制注销/重启，不自动切换用户输入源，不把 GIF 自动粘贴。
- 安装器只替换 App，保留 `~/Library/Rime`、偏好和 Keychain；升级后若菜单异常，先保留现场，不要反复重装。
