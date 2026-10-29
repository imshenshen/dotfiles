# 发布默认资源

`data/` 是打包用的公共方案资源快照（2026-10-14 固化；原始词库主要为 2024-12-20 安装版本），不是实时更新的白霜仓库。包含白霜、五笔、朙月拼音及公开词库、Lua、OpenCC 资源；各文件原有作者和来源信息保留。

来源：

- https://github.com/gaboolic/rime-frost （`licenses/rime-frost-LICENSE`）
- https://github.com/KyleBing/rime-wubi86-jidian （`licenses/wubi86-LICENSE`）
- https://github.com/rime/rime-luna-pinyin 及 Squirrel 预设资源（原有发行包授权文件随应用保留）

打包时 `prepare_release_data.sh` 会依次覆盖：

1. 上游固定 Squirrel 提交的 plum preset；
2. 本目录 `data/`；
3. 仓库根部的五个 `*.custom.yaml`、`wubi86_pinyin.schema.yaml`、`lua/wubi_pinyin_router.lua`、`lua/slash_literal.lua`；
4. `VoiceDefaults.plist`、许可文件和本说明。

`VoiceDefaults.plist` 保存右 Option 快捷键、豆包识别资源、停顿和自动空格等可分发默认值；运行时通过 `UserDefaults.register` 注册，已有设置优先。禁止包含 App ID、密钥、麦克风 UID、验收开关或用户词典。

`custom_phrase.txt` 在包内是空的个人词典模板。个人词条、`mixed_user_dictionary.json`、`*.userdb`、`installation.yaml`、`user.yaml`、Keychain 和机器身份绝不进入 PKG 或 Git。

安装脚本只在安装事务外安排 `SourceRecovery` 输入源恢复/首次注册；不在 postinstall 中编译 Rime 数据或写用户目录。完整构建和签名见仓库 `rime/docs/build.md`。
