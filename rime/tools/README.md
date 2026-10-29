# Rime 脚本地图

所有命令都在仓库根目录执行；脚本自动解析 `rime/.build` 和 `rime/dist`。

## 构建 / 发布

| 脚本 | 作用 | 前置 |
|---|---|---|
| `build_squirrel.sh` | 克隆/固定上游、应用五个前端补丁、构建 voice/cloud、Xcode、签名、打包、公证 | Xcode 26、CMake、证书、notary profile |
| `build_voice.sh` | 双架构 `RimeVoice.app` + `libRimeVoiceBridge.dylib` | Xcode、`native/voice` |
| `build_cloud_plugin.sh` | 双架构 `librime-cloud-pinyin.dylib` | `.build/squirrel` + Boost |
| `build_source_recovery.sh` | 双架构 `SourceRecovery` 安装辅助程序 | Xcode |
| `build_doubao_push.sh` | 编译/ad-hoc 签名/自测外部豆包词库 helper | 已安装 Mac 豆包引擎 |
| `prepare_release_data.sh` | 将发布默认数据 stage 到 App 并预编译 Rime | 已 stage 的 App |
| `package_squirrel.sh` | 重新签名、PKG、公证、装订已有构建件 | 已有 `.build/squirrel` 构建件 + notary profile |
| `sign_squirrel_app.py` | 从内到外签名嵌套代码 | Developer ID Application |
| `configure_notarization.sh` | 一次性配置 notarytool Keychain profile | Apple 开发者账号 |
| `notarize_squirrel.sh` | 提交/等待/装订/校验 PKG | profile |
| `install_squirrel.sh` | 备份并安装 `.build/squirrel/package/Squirrel.pkg` | 构建件、GUI 管理员认证 |

详细步骤见 [../docs/build.md](../docs/build.md)。

## 测试

| 脚本 | 作用 | 环境 |
|---|---|---|
| `test_voice_preferences.sh` | **主离线回归**：语音、词典、空格、符号/GIF、OSS 同步、云核心、Doubao state | 无 GUI/网络/Keychain |
| `test_slash_palette.sh` | `/fh`/`/gif` 状态机、目录、GIF、面板样式；含符号生成器检查 | 无 |
| `test_rime_sync.sh` | OSS 签名/加密/合并/锁/双机；`RIME_SYNC_AK/SK` 可选真实 OSS | 可选网络 |
| `test_cloud_core.sh` | 编译运行 `tests/cloud_core_test.cc` | clang++ |
| `test_voice.sh` | Apple 本地语音 + 编辑/历史/手动恢复 | `say -v Tingting` |
| `test_doubao_voice.sh` | 豆包协议/Stream/本机回环 mock | Node.js |
| `test_voice_rewrite.sh` | 重写 URLProtocol mock | 无 |
| `test_voice_hud.sh` | HUD 位置/行为 | macOS GUI |
| `test_input_source_migration.sh` | 输入源偏好迁移 | `.build/squirrel/sources` |
| `test_source_recovery.sh` | SourceRecovery + installer_policy | Xcode |
| `../tests/installer_policy_test.py` | 安装器策略文本 | 无 |
| `../tests/notarization_workflow_test.py` | 假 notarytool 流程 | Python |
| `../tests/release_defaults_test.py` | 隔离部署包默认数据 | 已构建 App |
| `../tests/release_registration_test.py` | LaunchServices 注册 | GUI |

测试矩阵和人工验收见 [../docs/testing.md](../docs/testing.md)。

## 研究 / 诊断

这些工具不进入构建和安装包，使用时只读写本机/临时数据：

- `probe_cloud.py`：公开拼音样本探测搜狗/Google/百度。
- `research_doubao_dictionary.py`：版本固定、只读/合成词库的豆包词库研究。
- `doubao_sync_state.py`：只读同步状态解码；`../tests/test_doubao_sync_state.py` 覆盖。
- `debug_keyboard_spacing.sh`：开/收集/关限时键盘间距元数据日志，不记录正文。

## 生成器

- `generate_symbol_catalog.py`：从 `distribution/data/symbols.yaml` 生成 `native/voice/SlashSymbolData.swift`；用 `--check` 检查漂移。
