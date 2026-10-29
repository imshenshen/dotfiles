# 测试

测试分四层：静态检查、离线回归、需要本机环境的专项/实时测试、桌面人工验收。模拟测试通过不能替代 IMK、麦克风、系统输入源、剪贴板或真实 OSS 双机验收。

## 1. 静态检查

```sh
git diff --check
bash -n rime/tools/*.sh
bash -n rime/distribution/scripts/preinstall rime/distribution/scripts/postinstall
python3 -m py_compile rime/tools/*.py rime/tests/*.py
```

符号生成器：

```sh
python3 rime/tools/generate_symbol_catalog.py --check
```

## 2. 主离线回归

```sh
bash rime/tools/test_voice_preferences.sh
```

这是日常改动的默认入口，覆盖：

- 语音快捷键、格式化、词典、手动编辑保护、剪贴板、设备/音频配置、蓝牙样本
- 直接 ASCII 空格、iTerm2 边界、方言/历史、`/fh`/`/gif` 状态机、符号目录、GIF 下载/剪贴板、非激活面板
- OSS 同步的签名、加密、合并/删除/冲突、userdb 路径、无 DELETE 锁和连接探测
- 云候选 `core.h` 的排序、缓存、LRU、二进制边界（`test_cloud_core.sh`）
- Doubao 同步状态的只读解码（`test_doubao_sync_state.py`）

它不需要麦克风、真实云账号、Keychain、GUI 或用户词典；只写 `.build/` 和临时目录。

单项：

```sh
bash rime/tools/test_slash_palette.sh
bash rime/tools/test_rime_sync.sh
bash rime/tools/test_cloud_core.sh
```

`test_slash_palette.sh` 会先验证 `SlashSymbolData.swift` 与 `distribution/data/symbols.yaml` 一致。`test_rime_sync.sh` 默认只跑离线；设置 `RIME_SYNC_AK`/`RIME_SYNC_SK` 才跑真实 OSS 双临时客户端测试，测试使用唯一 `rime-sync-live-<uuid>/` 前缀，不写真实词库。

## 3. 专项离线测试

```sh
bash rime/tools/test_voice.sh          # 需要 say -v Tingting；会构建 voice helper
bash rime/tools/test_doubao_voice.sh   # 需要 Node.js；本机回环 mock，无真实账号
bash rime/tools/test_voice_rewrite.sh  # URLProtocol 注入，无真实模型
bash rime/tools/test_source_recovery.sh
bash rime/tools/test_input_source_migration.sh  # 需要 .build/squirrel/sources
bash rime/tools/test_voice_hud.sh      # 需要 macOS GUI 会话
```

`test_source_recovery.sh` 同时执行 `rime/tests/installer_policy_test.py`，检查安装器策略文本。`test_input_source_migration.sh` 依赖已 patch 的上游 checkout；没有 `.build/squirrel` 时不应把它当作已通过。`test_voice_hud.sh` 只操作测试自己的窗口，不读其他应用输入，但需要可用的 GUI 会话。

## 4. 发布/安装包

构建后：

```sh
python3 rime/tests/release_defaults_test.py \
  rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
python3 rime/tests/notarization_workflow_test.py
```

`release_defaults_test.py` 在隔离目录部署包内默认数据，验证混输、方案、功能标记、无 symlink/用户数据/凭证，并确认预置默认值可被本地配置覆盖。`notarization_workflow_test.py` 使用假 notarytool 验证提交/恢复/装订流程。

需要 GUI/LaunchServices 的检查（只影响测试自己的暂存目录）：

```sh
python3 rime/tests/release_registration_test.py /path/to/Squirrel.app
```

## 5. 手动/实时验证

这些脚本不在主套件里，因为依赖已安装 App、真实网络或特定插件：

```sh
python3 rime/tests/verify_slash.py "/Library/Input Methods/Squirrel.app"
python3 rime/tests/verify_doubao_import.py "/Library/Input Methods/Squirrel.app"
python3 rime/tests/verify_local.py
python3 rime/tests/verify_mixed.py
python3 rime/tests/verify_cloud.py
python3 rime/tests/verify_cloud_live.py
RIME_SYNC_AK=... RIME_SYNC_SK=... bash rime/tools/test_rime_sync.sh
```

- `verify_slash.py` 用仓库 `distribution/data` 覆盖安装包中的旧数据，验证三方案直接 ASCII、`/fh`、`/bq`、`/mac`、`/gif`。
- `verify_doubao_import.py` 验证导入后的拼音词在混合五笔方案中的首选和提交。
- `verify_local.py` / `verify_mixed.py` 需要按 [cloud-pinyin](cloud-pinyin.md) 的说明先把源配置/词典部署到 `/tmp`。
- `verify_cloud.py` 需要 `RIME_CLOUD_TESTING=1` 构建的测试版云插件；`verify_cloud_live.py` 访问真实公开样例。
- 真实 OSS 测试只应在明确授权时使用凭证；凭证不要写进命令历史/仓库。

## 6. 手工验收矩阵

每次涉及对应路径的发布至少覆盖：

| 范围 | 验收 |
|---|---|
| Rime 配置 | 五笔/拼音混输、第五码顶字、`zz` 反查、直接 ASCII 半/全角、`/fh`、`/bq`、`/mac` |
| 语音 | TextEdit、iTerm2、浏览器/Codex；持续上屏、停顿、切应用、手动编辑保护、复制结果 |
| 符号/GIF | 面板不抢焦点、查询/分类/键盘/点击、GIF 只复制且能在微信/QQ/浏览器 ⌘V |
| 安装器 | 双击 PKG、管理员认证、输入源是否出现、菜单可切换、升级保留词库/偏好/Keychain |
| OSS 同步 | 两台机器各加一条词/别名/热词，保存并同步；另一台下拉；学习词双向出现 |
| Doubao 导入/推送 | 预览不写文件、合并后热词默认关闭；推送 helper 版本/hash、iPhone 可见、恢复本地备份不删云端 |

人工验收结果写进最终报告，注明测试机型、系统版本、安装包版本和未覆盖项。
