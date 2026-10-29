# Rime 开发规则（给后续 agent）

先读 [README.md](README.md)、[docs/architecture.md](docs/architecture.md)、[docs/build.md](docs/build.md)、[docs/testing.md](docs/testing.md)。只做与当前任务相关的 `rime/` 改动；仓库其他目录（fish、SpaceBar 等）不要顺手改。

## 源码权威位置

| 要改的东西 | 改这里 | 不要改 |
|---|---|---|
| Rime 方案 patch | 根目录 `*.custom.yaml`、`wubi86_pinyin.schema.yaml` | `~/Library/Rime`、`.build/` |
| Lua | `lua/*.lua` | 已生成的 `SharedSupport` |
| 公共方案/词库快照 | `distribution/data/`（大更新需单独评审） | 安装包内的 `build/` |
| Squirrel 前端 | `native/squirrel/*.patch` | `.build/squirrel` 里的上游 checkout |
| 语音/词典/同步 UI | `native/voice/*.swift` | `Squirrel.app` 内已签名的文件 |
| 云候选 | `native/cloud_pinyin/` | 前端候选窗逻辑 |
| 安装恢复 | `native/installer/SourceRecovery.swift`、`distribution/scripts/` | 系统输入源偏好 |
| 符号目录 | `tools/generate_symbol_catalog.py`，再生成 `native/voice/SlashSymbolData.swift` | 手改生成文件 |
| 构建/功能标记 | `tools/build_squirrel.sh`、`tools/prepare_release_data.sh` | 只改 LocalBuild.plist 产物 |

`.build/squirrel` 是固定上游提交的脏工作树：构建脚本会先反向撤销已知补丁、检查其他修改，再应用 `native/squirrel/` 的五个补丁。不要在里面 `git checkout`、`git clean` 或留下手工修改；正式源码在 patch 文件。

## 修改路径

- **Rime YAML/Lua**：改仓库源文件 → 在开发机重新部署/构建 → 用 `test_slash_palette.sh`、`verify_slash.py` 或隔离 harness 验证。不要靠软链把仓库文件挂进 `~/Library/Rime`。
- **前端补丁**：从已应用的 `.build/squirrel` 生成/更新 unified diff，保持顺序 `cloud-badge → voice-input → pkg-only-updates → release-safety → slash-commands`；先反向检查再应用。
- **语音桥/UI**：加到 `tools/build_voice.sh` 的源列表，随后 `build_squirrel.sh`；只跑 unit 测试不足以证明 IMK、焦点、麦克风或 GIF 粘贴。
- **发布数据**：只通过 `prepare_release_data.sh` 的复制白名单进入包内。个人词典、`mixed_user_dictionary.json`、`*.userdb`、`installation.yaml`、`user.yaml`、Keychain 和机器身份绝对不能进入 PKG 或 Git。
- **生成文件**：`SlashSymbolData.swift` 由 `generate_symbol_catalog.py` 生成；用 `--check` 验证。功能版本号以 `build_squirrel.sh` 写入的 `LocalBuild.plist` 为准，同时更新 README/architecture 的标记表。
- **文档**：当前行为写进 `docs/`，包号和验收历史只放在 `README` 的“当前状态”或 Git 提交，不把旧版本日志重新塞回功能文档。

## 命令

```sh
# 主离线回归（含 voice、dictionary、slash/GIF、sync、cloud core、Doubao state）
bash rime/tools/test_voice_preferences.sh

# 匹配当前构建件的包默认值检查
python3 rime/tests/release_defaults_test.py \
  rime/.build/squirrel/build/Build/Products/Release/Squirrel.app

# 完整构建（会签 App、打包、公证、staple）
bash rime/tools/build_squirrel.sh

# 仅重打包已有构建件
bash rime/tools/package_squirrel.sh

# 本机安装（GUI 认证；会备份）
bash rime/tools/install_squirrel.sh
```

测试层次、隐藏依赖和人工验收矩阵见 [docs/testing.md](docs/testing.md)。

## 必须先确认的禁区

没有当前用户的明确要求，不要：

- 运行 `build_squirrel.sh` 以外的公证上传；不要把包、词库、日志或凭证发到第三方。
- 安装/替换 `/Library/Input Methods/Squirrel.app`，或修改系统输入源/TCC/HIToolbox。
- 读取、打印、复制或提交 Keychain、`release.json`、个人词典、账号目录和用户学习库。
- 清理 `.build/`、`dist/` 或用户词库备份；这些是回滚和验收材料。
- 恢复“强制注销/重启”“GIF 自动粘贴”“软件模拟 ⌘V”“用 dotfiles 软链部署个人词典”等已被否决的方案。

## 产品不变量

- 默认语音键是**单按右 Option**；Shift 单独切换中英文，Shift+字母只输入大小写。不要恢复 pre-Rime Shift 拦截。
- 词条/别名/热词/学习快照跨机由 OSS 加密同步；Keychain 里只存本机凭证。换 Secret 会使旧远端 bundle 不可解密，需先明确迁移方案。
- 符号/GIF 面板非抢焦点；`/fh`/`/gif` 才打开；普通 `/`、`/bq`、`/mac` 保持 Rime 行为；GIF 只复制，用户自己 ⌘V。
- 安装器只替换 App，不写 `~/Library/Rime`、不自动切换输入源；首次安装/升级恢复用 `SourceRecovery`，不得强制注销。
- 云候选、豆包 ASR/重写、GIF provider 和 OSS 都是明确的数据外发路径；改动网络/隐私逻辑时同时更新 architecture 的数据流和 testing 的人工验收项。

## 完成标准

- 改文档/脚本：运行对应的 shell/Python 语法检查、链接检查和主离线套件；不要用“构建成功”代替测试。
- 改 Rime 配置：至少跑 `test_slash_palette.sh` 和隔离 harness；真实宿主行为另列人工验收。
- 改 native/发布数据：按 [docs/build.md](docs/build.md) 完整构建、签名、公证、装订并按 [docs/testing.md](docs/testing.md) 做包内检查；在报告中明确哪些项目仍是人工未验收。
- 所有报告只写已执行和已观察的结果；不要把模拟、headless 或协议 mock 说成真实桌面验收。
